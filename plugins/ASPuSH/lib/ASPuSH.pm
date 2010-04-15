package ASPuSH;
use strict;

sub stream_filter {
    my ( $cb, $author, $event_class, $profile ) = @_;
    my $url = $event_class->registry_entry->{url};
    my $ident = $profile->{ident};
    $url =~ s/ {{ident}} / $ident /xmsge;

    require MT::SubPop::Subscription;
    my $subsc = MT::SubPop::Subscription->load({
        topic     => $url,
        callback  => 'aspush',
    });
    return defined $subsc ? 0 : 1;
}

sub find_hub_link_from_xml {
    my ( $cb, %params ) = @_;
    my $x = $params{XPath};
    my $event = $params{event_class};
    $event = ref $event if ref $event;
    my $hub = $x->findvalue( '//link[@rel="hub"]/@href' )
        or return;
    my $topic = $params{url};
    my $author = $params{author}
        or return;
    my $info = {
        foreach     => $params{foreach},
        get         => $params{get},
        url         => "$topic",
        event_class => $event,
    };

    require MT::SubPop::Subscription;
    my $res = MT::SubPop::Subscription->subscribe(
        author_id => $author->id,
        hub_url   => "$hub",
        topic     => "$topic",
        callback  => 'aspush',
        info      => $info,
    ) or die "Failed to PuSH subscribe :" . MT::SubPop::Subscription->errstr;
}

sub update {
    my ( $sub, $xml ) = @_;
    #MT->log('Got ActionStreams Update via PuSH: '. $xml);
    my $info = $sub->info;
    my $event_class = $info->{event_class};
    my $author = MT->model('author')->load($sub->author_id);

    # FIXME: get it from $info and don't load all classes...

    # Make sure all classes are loaded.
    require ActionStreams::Event;
    for my $prevt (keys %{ MT->app->registry('action_streams') }) {
        ActionStreams::Event->classes_for_type($prevt);
    }

    my $items = $event_class->fetch_xpath(
        author  => $author,
        xml     => $xml,
        url     => $info->{url},
        %$info,
    );
    for my $item (@$items) {
        if ($item->{modified_on} && !$item->{created_on}) {
            $item->{created_on} = $item->{modified_on};
        }
    }
    return if !$items;

    eval {
        $event_class->build_results(
            items   => $items,
            stream  => $event_class->registry_entry,
            author  => $author,
            profile => $info,
        );
    };
    MT->log( "Error occured while building ActionStreams records: $@" ) if $@;

    ## build index pages.
    my $plugin = MT->component('ActionStreams');
    my $pd_iter = MT->model('plugindata')->load_iter({
        plugin => $plugin->key,
        key => { like => 'configuration:blog:%' }
    });

    my %rebuild;
    while ( my $pd = $pd_iter->() ) {
        next unless $pd->data('rebuild_for_action_stream_events');
        my ($blog_id) = $pd->key =~ m/:blog:(\d+)$/;
        $rebuild{$blog_id} = 1;
    }

    for my $blog_id (keys %rebuild) {
        my $blog = MT->model('blog')->load( $blog_id ) or next;
        MT->publisher->rebuild_indexes( Blog => $blog );
    }
}

1;
