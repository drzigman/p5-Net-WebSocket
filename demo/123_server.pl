#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Try::Tiny;

use HTTP::Request ();
use IO::Socket::INET ();
use IO::Select ();

use FindBin;
use lib "$FindBin::Bin/../lib";

use lib "$FindBin::Bin/lib";
use NWDemo ();

use Net::WebSocket::Endpoint::Server ();
use Net::WebSocket::Parser ();
use Net::WebSocket::Streamer::Server ();

my $host_port = $ARGV[0] || die "Need host:port or port!\n";

if (index($host_port, ':') == -1) {
    substr( $host_port, 0, 0 ) = '127.0.0.1:';
}

my ($host, $port) = split m<:>, $host_port;

my $server = IO::Socket::INET->new(
    LocalHost => $host,
    LocalPort => $port,
    ReuseAddr => 1,
    Listen => 2,
);

while ( my $sock = $server->accept() ) {
    fork and next;

    $sock->autoflush(1);

    NWDemo::handshake_as_server($sock);

    NWDemo::set_signal_handlers_for_server($sock);

    my $parser = Net::WebSocket::Parser->new($sock);

    $sock->blocking(0);

    my $s = IO::Select->new($sock);

    my $sent_ping;

    my $ept = Net::WebSocket::Endpoint::Server->new(
        parser => $parser,
        out => $sock,
    );

    my $streamer = Net::WebSocket::Streamer::Server->new('text');

    my $cur_number = 0;

    while (!$ept->is_closed()) {
        my ( $rdrs_ar, $s, $errs_ar ) = IO::Select->select( $s, $s, $s, 1 );

        my $is_final = ($cur_number == 2);

        my $method = $is_final ? 'create_final' : 'create_chunk';

        syswrite(
            $sock,
            $streamer->$method($cur_number)->to_bytes(),
        );

        $cur_number++;
        $cur_number %= 3;

        if ($is_final) {
            $streamer = Net::WebSocket::Streamer::Server->new('text');
        }

        if ($errs_ar && @$errs_ar) {
            $s->remove($sock);
            last;
        }

        if ( $rdrs_ar && @$rdrs_ar ) {
            try {
                $ept->get_next_message();   #we don’t care what it is
            }
            catch {
                if (!try { $_->isa('Net::WebSocket::X::ReceivedClose') } ) {
                    local $@ = $_;
                    die;
                }
            };
        }

        sleep 1;
    }

    exit;
}
