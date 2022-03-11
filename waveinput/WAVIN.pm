#
#

package Plugins::WaveInput::WAVIN;

use strict;
use base qw(Slim::Player::Pipeline);
use Slim::Utils::Strings qw(string);
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;



Slim::Player::ProtocolHandlers->registerHandler('wavin', __PACKAGE__);

my $log		= logger('plugin.waveinput');
my $prefs	= preferences('plugin.waveinput');


sub isRemote { 1 } 

sub new {

	my $class = shift;
	my $args  = shift;
	my $transcoder = $args->{'transcoder'};
	my $url        = $args->{'url'} ;
	my $client     = $args->{'client'};

	my $restoredurl;

	$restoredurl = $url;
	$restoredurl =~ s|^wavin:||;

	Slim::Music::Info::setContentType('pcm', 'wavin');

	my $command = Slim::Player::TranscodingHelper::tokenizeConvertCommand2( $transcoder, $restoredurl, $url, 1, 1);
	$log->info("WaveInput command =\'$command\'");

	my $self = $class->SUPER::new(undef, $command);

	${*$self}{'contentType'} = $transcoder->{'streamformat'};

	return $self;
}


sub canDoAction {
	my ( $class, $client, $url, $action ) = @_;
	$log->info("Action=$action");
	if (($action eq 'pause') && $prefs->get('pausestop') ) {
		$log->info("Stopping track because pref is set yo stop");
		return 0;
	}
	
	return 1;
}

sub canHandleTranscode {
	my ($self, $song) = @_;
	
	return 1;
}

sub getStreamBitrate {
	my ($self, $maxRate) = @_;
	
	return Slim::Player::Song::guessBitrateFromFormat(${*$self}{'contentType'}, $maxRate);
}

sub isAudioURL { 1 }

# XXX - I think that we scan the track twice, once from the playlist and then again when playing
sub scanUrl {
	my ( $class, $url, $args ) = @_;
	
	Slim::Utils::Scanner::Remote->scanURL($url, $args);
}

sub canDirectStream {
	return 0;
}

sub contentType 
{
	my $self = shift;

	return ${*$self}{'contentType'};
}


sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;

	my $icon = Plugins::WaveInput::Plugin->_pluginDataFor('icon');

	$log->debug("Begin Function for $url $icon");

	
#	Slim::Music::Info::setCurrentTitle( $url, 'PC WaveInput'  );
	return {
#		title    =>  'WaveInput', 
		bitrate  =>  "CD ",
		icon   => $icon,
		cover  => $icon,
		type   => 'PC Sound WaveInput',
	};

}


1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
