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
    my $info = {
        foreach     => $params{foreach},
        get         => $params{get},
        url         => "$topic",
        event_class => $event,
    };

    require MT::SubPop::Subscription;
    my $res = MT::SubPop::Subscription->subscribe(
        author_id => MT->app->user->id,
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
    $event_class->build_results(
        items   => $items,
        stream  => $event_class->registry_entry,
        author  => $author,
        profile => $info,
    );
}

1;
