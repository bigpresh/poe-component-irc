package POE::Component::IRC::Plugin::PlugMan;

use strict;
use warnings;
use POE::Component::IRC::Plugin qw( :ALL );

sub new {
  my $package = shift;
  my %parms = @_;
  $parms{ lc $_ } = delete $parms{ $_ } for keys %parms;
  return bless \%parms, $package;
}

##########################
# Plugin related methods #
##########################

sub PCI_register {
  my ($self,$irc) = @_;

  if ( $self->{botowner} and !$irc->isa('POE::Component::IRC::State') ) {
     warn "This plugin must be loaded into POE::Component::IRC::State or subclasses\n";
     return 0;
  }

  $self->{irc} = $irc;

  $irc->plugin_register( $self, 'SERVER', qw(public msg) );

  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = @_;
  delete $self->{irc};
  return 1;
}

sub S_public {
  my ($self,$irc) = splice @_, 0 , 2;
  my ($nick,$userhost) = ( split /!/, ${ $_[0] } )[0..1];
  return PCI_EAT_NONE unless $self->_bot_owner( $nick );
  my $channel = ${ $_[1] }->[0];
  my $what = ${ $_[2] };
  
  my $mynick = $irc->nick_name();
  my ($command) = $what =~ m/^\s*\Q$mynick\E[\:\,\;\.]?\s*(.*)$/i;
  return PCI_EAT_NONE unless $command;


  my (@cmd) = split(/ +/,$command);

  SWITCH: {
	my $cmd = uc ( shift @cmd );
	if ( $cmd eq 'PLUGIN_ADD' ) {
	  if ( $self->load( @cmd ) ) {
		$irc->yield( privmsg => $channel => 'Done.' );
	  } else {
		$irc->yield( privmsg => $channel => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_DEL' ) {
	  if ( $self->unload( @cmd ) ) {
		$irc->yield( privmsg => $channel => 'Done.' );
	  } else {
		$irc->yield( privmsg => $channel => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LIST' ) {
          my @aliases = keys %{ $irc->plugin_list() };
          if ( @aliases ) {
                $irc->yield( privmsg => $channel => 'Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( privmsg => $channel => 'No plugins loaded.' );
          }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_RELOAD' ) {
	  if ( $self->reload( @cmd ) ) {
		$irc->yield( privmsg => $channel => 'Done.' );
	  } else {
		$irc->yield( privmsg => $channel => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LOADED' ) {
          my @aliases = $self->loaded();
          if ( @aliases ) {
                $irc->yield( privmsg => $channel => 'Managed Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( privmsg => $channel => 'No managed plugins loaded.' );
          }
	  last SWITCH;
	}
  }

  return PCI_EAT_NONE;
}

sub S_msg {
  my ($self,$irc) = splice @_, 0 , 2;
  my ($nick,$userhost) = ( split /!/, ${ $_[0] } )[0..1];
  return PCI_EAT_NONE unless $self->_bot_owner( $nick );
  my $channel = ${ $_[1] }->[0];
  my $command = ${ $_[2] };
  
  my (@cmd) = split(/ +/,$command);
  SWITCH: {
	my $cmd = uc ( shift @cmd );
	if ( $cmd eq 'PLUGIN_ADD' ) {
	  if ( $self->load( @cmd ) ) {
		$irc->yield( notice => $nick => 'Done.' );
	  } else {
		$irc->yield( notice => $nick => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_DEL' ) {
	  if ( $self->unload( @cmd ) ) {
		$irc->yield( notice => $nick => 'Done.' );
	  } else {
		$irc->yield( notice => $nick => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LIST' ) {
          my @aliases = keys %{ $irc->plugin_list() };
          if ( @aliases ) {
                $irc->yield( notice => $nick => 'Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( notice => $nick => 'No plugins loaded.' );
          }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_RELOAD' ) {
	  if ( $self->reload( @cmd ) ) {
		$irc->yield( notice => $nick => 'Done.' );
	  } else {
		$irc->yield( notice => $nick => 'Nope.' );
	  }
	  last SWITCH;
	}
	if ( $cmd eq 'PLUGIN_LOADED' ) {
          my @aliases = $self->loaded();
          if ( @aliases ) {
                $irc->yield( notice => $nick => 'Managed Plugins [ ' . join(', ', @aliases ) . ' ]' );
          } else {
                $irc->yield( notice => $nick => 'No managed plugins loaded.' );
          }
	  last SWITCH;
	}
  }

  return PCI_EAT_NONE;
}

#########################
# Trust related methods #
#########################

sub _bot_owner {
  my $self = shift;
  my $who = $_[0] || return 0;
  my ($nick,$userhost);

  return unless $self->{botowner};

  if ( $who =~ /!/ ) {
	($nick,$userhost) = ( split /!/, $who )[0..1];
  } else {
	($nick,$userhost) = ( split /!/, $self->{irc}->nick_long_form($who) )[0..1];
  }

  return unless $nick and $userhost;

  $who = l_irc ( $nick ) . '!' . l_irc ( $userhost );

  if ( $self->{botowner} =~ /[\x2A\x3F]/ ) {
	my ($owner) = l_irc ( $self->{botowner} );
	$owner =~ s/\x2A/[\x01-\xFF]{0,}/g;
	$owner =~ s/\x3F/[\x01-\xFF]{1,1}/g;
	if ( $who =~ /$owner/ ) {
		return 1;
	}
  } elsif ( $who eq l_irc ( $self->{botowner} ) ) {
	return 1;
  }

  return 0;
}

###############################
# Plugin manipulation methods #
###############################

sub load {
  my ($self,$desc,$plugin) = splice @_, 0, 3;
  return unless $desc and $plugin;

  my $loaded = 0;

  $plugin .= '.pm' unless ( $plugin =~ /\.pm$/ );
  $plugin =~ s/::/\//g;

  eval { 
	require $plugin;
	$loaded = 1;
  };

  return 0 unless $loaded;

  $plugin =~ s/\.pm$//;
  $plugin =~ s/\//::/g;

  my $module = $plugin;

  my $object = $plugin->new( @_ );

  return 0 unless $object;
  
  my $args = [ @_ ];

  $self->{plugins}->{ $desc }->{module} = $module;

  my $return = $self->{irc}->plugin_add( $desc, $object );
  if ( $return ) {
	# Stash away arguments for use later by _reload.
	$self->{plugins}->{ $desc }->{args} = $args;
  } else {
	# Cleanup
	delete ( $self->{plugins}->{ $desc } );
  }
  return $return;
}

sub unload {
  my ($self,$desc) = splice @_, 0, 2;
  return unless $desc;

  my $plugin = $self->{irc}->plugin_del( $desc );
  return 0 unless $plugin;
  my $module = $self->{plugins}->{ $desc }->{module};
  delete $INC{$module};
  delete $self->{plugins}->{ $desc };
  return 1;
}

sub reload {
  my ($self,$desc) = splice @_, 0, 2;
  return unless $desc;

  my $plugin_state = $self->{plugins}->{ $desc };
  return 0 unless $plugin_state;
  print STDERR "Unloading plugin $desc\n" if $self->{debug};
  return 0 unless $self->unload( $desc );

  print STDERR "Loading plugin $desc " . $plugin_state->{module} . " [ " . join(', ',@{ $plugin_state->{args} }) . " ]\n" if $self->{debug};
  return 0 unless $self->load( $desc, $plugin_state->{module}, @{ $plugin_state->{args} } );
  return 1;
}

sub loaded {
  my $self = shift;
  return keys %{ $self->{plugins} };
}

###########################
# Miscellaneous functions #
###########################

sub u_irc {
  my $value = shift || return;
  $value =~ tr/a-z{}|/A-Z[]\\/;
  return $value;
}

sub l_irc {
  my $value = shift || return;
  $value =~ tr/A-Z[]\\/a-z{}|/;
  return $value;
}

1;
__END__
=head1 NAME

POE::Component::IRC::Plugin::PlugMan - a POE::Component::IRC plugin that provides plugin management services. 

=head1 SYNOPSIS

   use strict;
   use warnings;
   use POE qw(Component::IRC::State);
   use POE::Component::IRC::Plugin::PlugMan;

   my $botowner = 'somebody!*@somehost.com';
   my $irc = POE::Component::IRC::State->spawn();

   POE::Session->create( 
        package_states => [ 
                'main' => [ qw(_start irc_plugin_add) ],
        ],
   );

   sub _start {
     $irc->yield( register => 'all' );
     $irc->plugin_add( 'PlugMan' => POE::Component::IRC::Plugin::PlugMan->new( botowner => $botowner ) );
     undef;
   }

   sub irc_plugin_add {
     my ( $desc, $plugin ) = @_[ARG0,ARG1];
     
     if ( $desc eq 'PlugMan' ) {
	$plugin->load( 'Connector', 'POE::Component::IRC::Plugin::Connector' );
     }
     undef;
   }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::PlugMan is a POE::Component::IRC plugin management plugin. It provides support for
'on-the-fly' loading, reloading and unloading of plugin modules, via object methods that you can incorporate into
your own code and a handy IRC interface.

=head1 CONSTRUCTOR

=over

=item new

Takes two optional arguments:

   "botowner", an IRC mask to match against for people issuing commands via the IRC interface;
   "debug", set to a true value to see when stuff goes wrong;

Not setting a "botowner" effectively disables the IRC interface. 

If "botowner" is specified the plugin checks that it is being loaded into a
L<POE::Component::IRC::State> or sub-class and will fail to load otherwise.

Returns a plugin object suitable for feeding to L<POE::Component::IRC>'s plugin_add() method.

=back

=head1 METHODS

=over

=item load

Loads a managed plugin.

Takes two mandatory arguments, a plugin descriptor and a plugin package name. Any other arguments are used as
options to the loaded plugin constructor.

   $plugin->load( 'Connector', 'POE::Component::IRC::Plugin::Connector', delay, 120 );

Returns true or false depending on whether the load was successfully or not.

You may check $@ for error messages.

=item unload

Unloads a managed plugin.

Takes one mandatory argument, a plugin descriptor.

   $plugin->unload( 'Connector' );

Returns true or false depending on whether the unload was successfully or not.

=item reload

Unloads and loads a managed plugin, with applicable plugin options.

Takes one mandatory argument, a plugin descriptor.

   $plugin->reload( 'Connector' );

You may check $@ for error messages.

=item loaded

Takes no arguments.

   $plugin->loaded();

Returns a list of descriptors of managed plugins.

=back

=head1 IRC INTERFACE

The IRC interface is enabled by specifying a "botowner" mask to new(). Commands may be either invoked via
a PRIVMSG directly to your bot or in a channel by prefixing the command with the nickname of your bot. One
caveat, the parsing of the irc command is very rudimentary ( it merely splits the line on \s+ ). 

=over

=item plugin_add

Takes the same arguments as load().

=item plugin_del

Takes the same arguments as unload().

=item plugin_reload

Takes the same arguments as reload().

=item plugin_loaded

Returns a list of descriptors of managed plugins.

=item plugin_list

Returns a list of descriptors of *all* plugins loaded into the current PoCo-IRC component.

=back

=head1 AUTHOR

Chris 'BinGOs' Williams

=head1 SEE ALSO

L<POE::Component::IRC::State>

L<POE::Component::IRC::Plugin>
