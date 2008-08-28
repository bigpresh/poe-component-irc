use strict;
use warnings;
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Test::Harness;
use Socket;
use Test::More tests => 9;

my $irc = POE::Component::IRC->spawn( plugin_debug => 1 );
my $irc2 = POE::Component::IRC->spawn( plugin_debug => 1 );
my $ircd = POE::Component::IRC::Test::Harness->spawn(
    Alias     => 'ircd',
    Auth      => 0,
    AntiFlood => 0,
);

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001 
            irc_join
            irc_disconnected
            irc_dcc_request
            irc_dcc_done
        )],
    ],
);

$poe_kernel->run();

sub _start {
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $wheel = POE::Wheel::SocketFactory->new(
        BindAddress  => '127.0.0.1',
        BindPort     => 0,
        SuccessEvent => '_fake_success',
        FailureEvent => '_fake_failure',
    );

    if ($wheel) {
        my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
        $kernel->yield(_config_ircd => $port );
        $heap->{count} = 0;
        $wheel = undef;
        $kernel->delay(_shutdown => 60);
        return;
    }
    
    $kernel->yield('_shutdown');
}

sub _config_ircd {
    my ($kernel, $port) = @_[KERNEL, ARG0];
    
    $kernel->post( 'ircd' => 'add_i_line' );
    $kernel->post( 'ircd' => 'add_listener' => { Port => $port } );
    
    $irc->yield(register => 'all');
    $irc->yield(connect => {
        nick    => 'TestBot1',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });

    $irc2->yield(register => 'all');
    $irc2->yield(connect => {
        nick    => 'TestBot2',
        server  => '127.0.0.1',
        port    => $port,
        ircname => 'Test test bot',
    });
}

sub irc_001 {
    my $irc = $_[SENDER]->get_heap();
    pass('Logged in');
    $irc->yield(join => '#testchannel');
}

sub irc_join {
    my ($sender, $who, $where) = @_[SENDER, ARG0, ARG1];
    my $nick = ( split /!/, $who )[0];
    my $irc = $sender->get_heap();
    
    if ($nick eq $irc->nick_name()) {
        is($where, '#testchannel', 'Joined Channel Test');
    }
    else {
        $irc->yield(dcc => $nick => CHAT => '' => '' => 15);
    }
}

sub irc_dcc_request {
    my ($sender, $who, $type, $port, $cookie) = @_[SENDER,ARG0..ARG3];

    pass('Got dcc request');
    is($cookie->{addr}, '2130706433', 'Correct Address Test');
    $sender->get_heap()->yield('quit');
}

sub irc_dcc_done {
    pass('Got dcc timeout');
    $_[SENDER]->get_heap()->yield('quit');
}

sub irc_disconnected {
    my ($kernel, $heap) = @_[KERNEL, HEAP];
    pass('irc_disconnected');
    $heap->{count}++;
    $kernel->yield('_shutdown') if $heap->{count} == 2;
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $kernel->post(ircd => 'shutdown');
    $irc->yield('shutdown');
    $irc2->yield('shutdown');
}

