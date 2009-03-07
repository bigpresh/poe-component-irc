package POE::Component::IRC::Plugin::BotTraffic;

use strict;
use warnings;
use POE::Component::IRC::Plugin qw( :ALL );
use POE::Filter::IRCD;
use POE::Filter::IRC::Compat;

our $VERSION = '6.04';

sub new {
    my ($package) = @_;
    return bless {
        PrivEvent => 'irc_bot_msg',
        PubEvent => 'irc_bot_public',
        ActEvent => 'irc_bot_action',
    }, $package;
}

sub PCI_register {
    my ($self, $irc) = splice @_, 0, 2;

    $self->{filter} = POE::Filter::IRCD->new();
    $self->{compat} = POE::Filter::IRC::Compat->new();
    $irc->plugin_register( $self, 'USER', qw(privmsg) );
    return 1;
}

sub PCI_unregister {
    return 1;
}

sub U_privmsg {
    my ($self, $irc) = splice @_, 0, 2;
    my $output = ${ $_[0] };
    my ($lines) = $self->{filter}->get([ $output ]);

    for my $line ( @{ $lines } ) {
        my $text = $line->{params}->[1];
        if ($text =~ /^\001/) {
            my $ctcp_event = shift( @{ $self->{compat}->get([$line]) } );
            next if $ctcp_event->{name} ne 'ctcp_action';
            my $event = $self->{ActEvent};
            $irc->send_event( $event => @{ $ctcp_event->{args} }[1..2] );
        }
        else {
            for my $recipient ( split(/,/,$line->{params}->[0]) ) {
                my $event = $self->{PrivEvent};
                $event = $self->{PubEvent} if ( $recipient =~ /^(\x23|\x26|\x2B)/ );
                $irc->send_event( $event => [ $recipient ] => $text );
            }
        }
    }

    return PCI_EAT_NONE;
}

1;
__END__

=head1 NAME

POE::Component::IRC::Plugin::BotTraffic - A PoCo-IRC plugin that generates
events when you send messages

=head1 SYNOPSIS

 use POE::Component::IRC::Plugin::BotTraffic;

 $irc->plugin_add( 'BotTraffic', POE::Component::IRC::Plugin::BotTraffic->new() );

 sub irc_bot_public {
     my ($kernel, $heap) = @_[KERNEL, HEAP];
     my $channel = $_[ARG0]->[0];
     my $what = $_[ARG1];

     print "I said '$what' on channel $channel\n";
     return;
 }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::BotTraffic is a L<POE::Component::IRC|POE::Component::IRC>
plugin. It watches for when your bot sends privmsgs to the server. If your bot
sends a privmsg to a channel (ie. the recipient is prefixed with '#', '&', or
'+') it generates an C<irc_bot_public> event, otherwise it will generate an
C<irc_bot_msg> event.

These events are useful for logging what your bot says.

=head1 METHODS

=head2 C<new>

No arguments required. Returns a plugin object suitable for feeding to
L<POE::Component::IRC|POE::Component::IRC>'s C<plugin_add> method.

=head1 OUTPUT

These are the events generated by the plugin. Both events have C<ARG0> set
to an arrayref of recipients and C<ARG1> the text that was sent.

=head2 C<irc_bot_public>

C<ARG0> will be an arrayref of recipients. C<ARG1> will be the text sent.

=head2 C<irc_bot_msg>

C<ARG0> will be an arrayref of recipients. C<ARG1> will be the text sent.

=head2 C<irc_bot_action>

C<ARG0> will be an arrayref of recipients. C<ARG1> will be the text sent.

=head1 AUTHOR

Chris 'BinGOs' Williams [chris@bingosnet.co.uk]

=head1 SEE ALSO

L<POE::Component::IRC>

=cut
