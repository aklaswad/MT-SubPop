package MT::SubPop::Util;
use strict;
use warnings;
use MT;
use Digest::SHA1 qw( sha1_hex );

sub secret {
    ##TODO: return string that is unique in each MT install.
    return 'mtpubsubhubbub';
}

sub generate_token {
    ##TODO: return string that is unique in each invoke.
    return sha1_hex( secret() . time() );
}

1;

