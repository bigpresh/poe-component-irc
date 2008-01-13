package POE::Component::IRC::Plugin::FollowTail;

use strict;
use warnings;
use Carp;
use POE qw(Wheel::FollowTail);
use POE::Component::IRC::Plugin qw( :ALL );
use vars qw($VERSION);

$VERSION = '0.01';

sub new {
  my $package = shift;
  my %params = @_;
  $params{lc $_} = delete $params{$_} for keys %params;
  croak "$package requires a valid 'filename' attribute\n"
	unless $params{filename} and -e $params{filename};
  my $self = bless \%params, $package;
  return $self;
}

sub PCI_register {
  my ($self,$irc) = splice @_, 0, 2;
  $self->{irc} = $irc;
  $self->{session_id} = POE::Session->create(
	object_states => [
	  $self => [ qw(_start _shutdown _input _error _reset) ],
	],
  )->ID();
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
  delete $self->{irc};
  $poe_kernel->post( $self->{session_id} => '_shutdown' );
  $poe_kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ );
  return 1;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{wheel} = POE::Wheel::FollowTail->new(
    Filename     => $self->{filename},
    InputEvent   => '_input',
    ErrorEvent   => '_error',
    ResetEvent   => '_reset',
    ( $self->{filter} and $self->{filter}->isa('POE::Filter') ? ( Filter => $self->{filter} ) : () ),
  );
  return;
}

sub _shutdown {
  my ($kernel,$self,$term) = @_[KERNEL,OBJECT,ARG0];
  delete $self->{wheel};
  $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ ) if $term;
  return;
}

sub _input {
  my ($kernel,$self,$input) = @_[KERNEL,OBJECT,ARG0];
  $self->{irc}->_send_event( 'irc_tail_input', $self->{filename}, $input );
  return;
}

sub _error {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{irc}->_send_event( 'irc_tail_error', $self->{filename}, @_[ARG0..ARG2] );
  $kernel->yield('_shutdown','TERM');
  return;
}

sub _reset {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{irc}->_send_event( 'irc_tail_reset', $self->{filename} );
  return;
}


1;
__END__

=head1 NAME

POE::Component::IRC::Plugin::FollowTail - a PoCo-IRC to follow the tail of an ever-growing file

=head1 SYNOPSIS

  use POE qw(Component::IRC Component::IRC::Plugin::FollowTail);

  my $nickname = 'Flibble' . $$;
  my $ircname = 'Flibble the Sailor Bot';
  my $ircserver = 'irc.blahblahblah.irc';
  my $filename = '/some/such/file/here';

  my @channels = ( '#Blah', '#Foo', '#Bar' );

  my $irc = POE::Component::IRC->spawn( 
        nick => $nickname,
        server => $ircserver,
        port => $port,
        ircname => $ircname,
  ) or die "Oh noooo! $!";

  POE::Session->create(
        package_states => [
                'main' => [ qw(_start irc_001 irc_tail_input irc_tail_error irc_tail_reset) ],
        ],
  );

  $poe_kernel->run();
  exit 0;

  sub _start {
    $irc->plugin_add( 'FollowTail' => 
	POE::Component::IRC::Plugin::FollowTail->new( 
		filename => $filename,
	) );
    $irc->yield( register => 'all' );
    $irc->yield( connect => { } );
    undef;
  }

  sub irc_001 {
    $irc->yield( join => $_ ) for @channels;
    undef;
  }

  sub irc_tail_input {
    my ($kernel,$sender,$filename,$input) = @_[KERNEL,SENDER,ARG0,ARG1];
    $kernel->post( $sender, 'privmsg', $_, "$filename: $input" ) for @channels;
    return;
  }

  sub irc_tail_error {
    my ($kernel,$sender,$filename,$errnum,$errstring) = @_[KERNEL,SENDER,ARG0..ARG2];
    $kernel->post( $sender, 'privmsg', $_, "$filename: ERROR: $errnum $errstring" ) for @channels;
    $irc->plugin_del( 'FollowTail' );
    return;
  }

  sub irc_tail_reset {
    my ($kernel,$sender,$filename) = @_[KERNEL,SENDER,ARG0];
    $kernel->post( $sender, 'privmsg', $_, "$filename: RESET EVENT" ) for @channels;
    return;
  }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::FollowTail is a L<POE::Component::IRC> plugin that uses
L<POE::Wheel::FollowTail> to follows the end of an ever-growing file. It generates 
'irc_tail_' prefixed events for each new record that is appended to its file.

=head1 CONSTRUCTOR

=over

=item new

Takes two arguments:

  'filename', the name of the file to tail, mandatory;
  'filter', a POE::Filter object to pass to POE::Wheel::FollowTail, optional;

=back

=head1 EVENTS

The plugin generates the following additional L<POE::Component::IRC> events:

=over

=item irc_tail_input

Emitted for every complete record read. ARG0 will be the filename, ARG1 the record which was read.

=item irc_tail_error

Emitted whenever an error occurs. ARG0 will be the filename, ARG1 and ARG2 hold numeric and 
string values for $!, respectively.

=item irc_tail_reset

Emitted every time a file is reset. ARG0 will be the filename.

=back

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Component::IRC>

L<POE::Wheel::FollowTail>
