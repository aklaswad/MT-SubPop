package MT::SubPop::Subscription;
use strict;
use warnings;
use base qw( MT::Object );
use MT;
use MT::SubPop::Util;

## Constants
sub ERROR           { 0 }
sub FOR_SUBSCRIBE   { 1 }
sub ACTIVE          { 2 }
sub FOR_UNSUBSCRIBE { 3 }

__PACKAGE__->install_properties({
    column_defs => {
        hub_url      => 'text',
        topic        => 'text',
        author_id    => 'integer',
        status       => 'integer',
        verify_token => 'string(75)',
        callback     => 'text',
    },
    datasource  => 'subpop',
    primary_key => 'verify_token',
});

sub class_label { 'SubPop Subscription' }

sub subscribe {
    my $self = shift;
    my ( %opts ) = @_;
    if ( !ref $self ) {
        my @subs = __PACKAGE__->load({
            hub_url => $opts{hub_url},
            topic   => $opts{topic},
        });
        if ( scalar @subs ) {
            my @same = grep {
                $_->author_id == $opts{author_id}
                && $_->callback eq $opts{callback}
            } @subs;
            if ( scalar @same ) {
                MT->log('PubSubHubbub: Duplicate subscription');
                return $same[0];
            }
            else {
                my $clone = $subs[0]->clone;
                $clone->author_id($opts{author_id});
                $clone->callback($opts{callback});
                $clone->save;
                return $clone;
            }
        }
        else {
            $self = __PACKAGE__->new;
            my @columns = qw(
                hub_url topic author_id callback
            );
            for my $col ( @columns ) {
                my $val = $opts{$col};
                return $self->error(
                    MT->translate(
                        'SubPop can\'t subscribe without [_1]', $col
                    )
                ) if !$val;
                $self->$col($val);
            }
        }
    }
    if ( ( $self->status || 0 ) == ACTIVE() ) {
        return $self->error(
            MT->translate(
                'This Subscription was already active.',
            )
        );
    }
    $self->status( FOR_SUBSCRIBE() );
    $self->verify_token( MT::SubPop::Util::generate_token() );
    $self->save
        or die;
    $self->_request('subscribe');
}

sub unsubscribe {
    my $self = shift;
    my ( %opts ) = @_;
    if ( !ref $self ) {
        $self = __PACKAGE__->load( \%opts );
    }
    return __PACKAGE__->error('no such subscription') unless $self;
    my $count = __PACKAGE__->count({
        hub_url => $self->hub_url,
        topic   => $self->topic,
    });
    if ( 1 < $count ) {
        ## No need to unsubscribe to hub. just remove the record and return.
        $self->remove;
        return;
    }
    $self->status( FOR_UNSUBSCRIBE() );
    $self->save or die;
    $self->_request('unsubscribe');
}

sub _request {
    my $self = shift;
    my ( $mode ) = @_; # subscribe or unsubscribe
    return $self->error( 'Mode was not given.' )
        if !$mode || ($mode ne 'subscribe' && $mode ne 'unsubscribe');
    my $end_point = MT->config->SubPopScript || ( MT->app->base . MT->config->CGIPath . 'mt-subpop.cgi' );
    my $params = {
        mode         => $mode,
        callback     => $end_point,
        topic        => $self->topic,
        verify       => 'sync',
        secret       => MT::SubPop::Util::secret(),
        verify_token => $self->verify_token,
    };
    my $param = join( '&',
        map { 'hub.' . $_ . '=' . $params->{ $_ } } keys %$params );
    my $ua = MT->new_ua;
    my $req = HTTP::Request->new( POST => $self->hub_url );
    $req->content_type('application/x-www-form-urlencoded');
    $req->content( $param );
    my $res = $ua->request($req);
    ## Check the status code.
    ## Hub may returns 204 if subscription was accepted.
    my $status = $res->code;
    if ( $status != 204 ) {
        my $message = MT->translate(
            'Subscription was refused by Hub: [_1] [_2]',
            $status,
            $res->content,
        );
        MT->log( $message );
        return $self->error( $message );
    }
    ## Successed to subscribe!
    MT->log(
        MT->translate(
            'SubPop: [_1] for topic [_2] was accepted by hub [_3].',
            $mode,
            $self->topic,
            $self->hub_url,
    ));
    return 1;
}

1;

__END__

=head1 NAME

MT-SubPop

=head1 SYNOPSIS

    require MT::SubPop::Subscription;
    MT::SubPop::Subscription->subscribe(
        hub_url   => 'http://hub.example.org/subscribe_script.cgi',
        topic     => 'http://publisher.example.com/atom.xml',
        callback  => '$PluginFoo::PluginFoo::update_handler',
        author_id => $author->id,
    );

=head1 DESCRIPTION

I<MT::SubPop::Subscription> class supports to subscribe for I<Hub> which supports I<PubSubHubbub> protocol.


I<MT::SubPop::Subscription>クラスはPubSubHubbubプロトコルに対応したHubへの登録をサポートします。

=head1 USAGE

=head2 subscribe

subscribe for new topic.


=over 4

=item * hub_url

=item * topic

=item * callback

=item * author_id

=back

=head2 unsubscribe

=cut
