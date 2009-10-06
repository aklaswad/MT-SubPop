package MT::App::SubPop;
use strict;
use MT;
use base qw( MT::App );

use MT::SubPop::Util;
use Encode;
sub id {'subpop'}

sub init {
    my $app = shift;
    $app->{no_read_body} = 1
        if $app->request_method eq 'POST';
    $app->SUPER::init(@_) or return $app->error("Initialization failed");
    $app->request_content
        if $app->request_method eq 'POST';
    $app;
}

sub mode {
    my $app = shift;
    return $app->request_method eq 'POST' ? 'update' : 'subscribe';
}

sub subscribe {
    my $app = shift;
    my $token     = $app->param('hub.verify_token');
    my $topic     = $app->param('hub.topic');
    my $challenge = $app->param('hub.challenge');
    my $mode      = $app->param('hub.mode');

    ## check is this subscribe request truely mine.
    my $sub = MT->model('subpop')->load({ verify_token => $token });
    return $app->subscribe_error("Can't find subscription data $token")
        unless defined $sub;
    return $app->subscribe_error("unknown topic $topic")
        if $sub->topic ne $topic;

    if ( $mode eq 'subscribe') {
        if ( $sub->status == $sub->FOR_SUBSCRIBE() ) {
            $sub->status( $sub->ACTIVE() );
            $sub->save;
            MT->log("Success to subscribe topic $topic");
        }
    }
    elsif ( $mode eq 'unsubscribe' ) {
        if ( $sub->status == $sub->FOR_UNSUBSCRIBE() ) {
            $sub->remove;
            MT->log("Success to unsubscribe topic $topic");
        }
    }
    else {
        MT->log("PubSubHubbub: got unknown access for $mode");
        return $app->subscribe_error;
    }
    $app->response_code(200);
    $app->response_content_type('text/plain');
    return $challenge;
}

sub subscribe_error {
    my $app = shift;
    my ($mess) = @_;
    MT->log("Bad Subscription: $mess");
    $app->response_code(404);
    return '';
}

sub update {
    my $app = shift;
    if ( !$app->verify_update ) {
        ## this is spam post.
        ## should return fake OK status.
        $app->response_code(200);
        $app->response_content_type('text/plain');
        MT->log('PubSubHubbub: Got bad update from hub');
        return 1;
    }
    my $xml = $app->request_content;
    $xml = Encode::decode_utf8($xml);

    ## get topic.
    ## TODO: this seems no good, but I can't find another way to know topic address from this ping...
    my $topic;
    require XML::XPath;
    my $x = XML::XPath->new( xml => $xml );
    $topic = $x->findvalue( '//feed/link[@rel="http://schemas.google.com/g/2005#feed"]/@href' ); 
    $topic = "$topic"; # cast from XML::XPath::Scalar to perl scalar.

    my @subs = MT->model('subpop')->load({ topic => $topic });
    my %callbacks;
    for my $sub ( @subs ) {
        $callbacks{ $sub->callback } ||= [];
        push @{ $callbacks{ $sub->callback } }, $sub;
    }
    for my $callback ( keys %callbacks ) {
        my $func = MT->registry('subpop_callbacks', $callback);
        my $each_author;
        if ( ref $func eq 'HASH') {
            $each_author = $func->{each_author};
            $func = $func->{handler};
        }
        if ( !ref $func ) {
            $func = MT->handler_to_coderef( $func );
        }
        ## Now it's time to run callbacks
        if ( $each_author ) {
            my $subs = $callbacks{$callback};
            for my $sub ( @$subs ) {
                $func->( $sub, $xml );
            }
        }
        else {
            my $sub = $callbacks{$callback}->[0];
            $func->( $sub, $xml );
        }
    } 
    return 1;
}

sub verify_update {
    my $app = shift;
    my $hubsig = $app->get_header('X-Hub-Signature');
    $hubsig =~ s/^sha1\=//;
    my $body = $app->request_content;
    my $secret = MT::SubPop::Util::secret;
    require Digest::HMAC_SHA1;
    my $expected = Digest::HMAC_SHA1::hmac_sha1_hex($body, $secret);
    return $hubsig eq $expected ? 1 : 0;
}

## TODO: to know topic from pathinfo, in future release.
sub _get_params {
    my $app = shift;
    my $topic = $app->param('topic');
    unless ( $topic ) {
        if ( my $pi = $app->path_info ) {
            $pi =~ s!^/!!;
            my $endpoint = $app->config('SubPopScript')
                         || ( MT->config->CGIPath . 'mt-subpop.cgi' );
            $pi =~ s!.*\Q$endpoint\E/!!;
            $topic = $pi;
        }
    }
    $topic;
}

1;

