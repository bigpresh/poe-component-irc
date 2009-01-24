use strict;
use warnings;
use lib 't/inc';
use POE qw(Wheel::SocketFactory);
use POE::Component::IRC;
use POE::Component::IRC::Plugin::BotTraffic;
use POE::Component::Server::IRC;
use Socket;
use Test::More tests => 6;

my $irc = POE::Component::IRC->spawn( plugin_debug => 1 );
my $ircd = POE::Component::Server::IRC->spawn(
    Alias     => 'ircd',
    Auth      => 0,
    AntiFlood => 0,
);
$irc->plugin_add(BotTraffic => POE::Component::IRC::Plugin::BotTraffic->new());

POE::Session->create(
    package_states => [
        main => [qw(
            _start
            _config_ircd 
            _shutdown 
            irc_001 
            irc_join
            irc_disconnected
            irc_bot_public
            irc_bot_msg
            irc_bot_action
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
    $kernel->post( 'ircd' => 'add_listener' => Port => $port);
    
    $irc->yield(register => 'all');
    $irc->yield(connect => {
        nick    => 'TestBot1',
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

    pass('Joined channel');
    $irc->yield(privmsg => '#testchannel', 'A public message');
}

sub irc_bot_public {
    my ($sender, $targets, $text) = @_[SENDER, ARG0, ARG1];
    my $irc = $sender->get_heap();

    is($text, 'A public message', 'irc_bot_public');
    $irc->yield(privmsg => $irc->nick_name(), 'A private message');
}

sub irc_bot_msg {
    my ($sender, $targets, $text) = @_[SENDER, ARG0, ARG1];
    my $irc = $sender->get_heap();

    is($text, 'A private message', 'irc_bot_msg');
    $irc->yield(ctcp => 'TestBot1', 'ACTION some action');
}

sub irc_bot_action {
    my ($sender, $targets, $text) = @_[SENDER, ARG0, ARG1];
    my $irc = $sender->get_heap();

    is($text, 'some action', 'irc_bot_action');
    $irc->yield('quit');
}

sub irc_disconnected {
    my ($kernel) = $_[KERNEL];
    pass('irc_disconnected');
    $kernel->yield('_shutdown');
}

sub _shutdown {
    my ($kernel) = $_[KERNEL];
    $kernel->alarm_remove_all();
    $kernel->post(ircd => 'shutdown');
    $irc->yield('shutdown');
}

