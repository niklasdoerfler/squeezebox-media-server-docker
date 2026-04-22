#
#

package Plugins::WaveInput::WAVIN;

use strict;
use base qw(Slim::Player::Pipeline);
use Slim::Utils::Strings qw(string);
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Network;
use File::Spec;
use File::Which;
use IO::Handle;

use constant CAN_IMAGEPROXY => ( Slim::Utils::Versions->compareVersions( $::VERSION, '7.8.0' ) >= 0 );

Slim::Player::ProtocolHandlers->registerHandler('wavin', __PACKAGE__);

my $log         = logger('plugin.waveinput');
my $prefs       = preferences('plugin.waveinput');
my $cachedir    = preferences( 'server' )->get( 'cachedir' );
if ( !-d File::Spec->catdir( "/tmp/wavinspotify" ) ) {
    mkdir( File::Spec->catdir( "/tmp/wavinspotify" ) );
}
if ( !-d File::Spec->catdir( "/tmp/wavinshairport" ) ) {
    mkdir( File::Spec->catdir( "/tmp/wavinshairport" ) );
}

my $oldartworkurl = '';
my $imageproxy_registered = 0;

sub isRemote { 1 }

sub bufferThreshold { 400 }

sub new {

	my $class = shift;
	my $args  = shift;
	my $transcoder = $args->{'transcoder'};
	my $url        = $args->{'url'} ;
	my $client     = $args->{'client'};

	my $restoredurl;

	$restoredurl = $url;
	$restoredurl =~ s|^wavin:||;

	Slim::Music::Info::setContentType($url, 'wavin');
	my $quality = preferences('server')->client($client)->get('lameQuality');

	my $command = Slim::Player::TranscodingHelper::tokenizeConvertCommand2( $transcoder, $restoredurl, $url, 1, $quality );
	$log->debug("WaveInput command =\'$command\'");

	my $self = $class->SUPER::new(undef, $command);

	${*$self}{'contentType'} = $transcoder->{'streamformat'};

	if ( CAN_IMAGEPROXY && !$imageproxy_registered ) {
		require Slim::Web::ImageProxy;
		Slim::Web::ImageProxy->import();
		Slim::Web::ImageProxy->registerHandler(
			match => qr/wavinspotify:image:/,
			func  => \&_getcover,
		);
		Slim::Web::ImageProxy->registerHandler(
			match => qr/wavinshairport:image:/,
			func  => \&_getshairportcover,
		);
		$imageproxy_registered = 1;
	}
	elsif ( !CAN_IMAGEPROXY ) {
		$log->error( "Imageproxy not supported! Covers disabled!" );
	}

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

	my $spotify_file   = '/tmp/wavinspotify/spotifymetadata';
	my $shairport_file = '/tmp/wavinshairport/shairportmetadata';

	# Use whichever metadata file was written more recently
	my $filename = $spotify_file;
	my $source   = 'Spotify';

	if ( -f $shairport_file ) {
		if ( !-f $spotify_file || (stat($shairport_file))[9] > (stat($spotify_file))[9] ) {
			$filename = $shairport_file;
			$source   = 'AirPlay';
		}
	}

	my $counter = 0;
	my $artist = '';
	my $title = '';
	my $artworkurl = '';

	if ( open(my $fh, '<:encoding(UTF-8)', $filename) ) {
		while (my $row = <$fh>) {
			chomp $row;
			if($counter == 0){ $artist = $row; }
			if($counter == 1){ $title = $row; }
			if($counter == 2){ $artworkurl = $row; }
			$counter=$counter+1;
		}
		close($fh);
	}
	else {
		$log->warn("Unable to open metadata file: $filename");
	}

	if ($artworkurl ne "") {
		# shairport cover art is served via imageproxy (local file)
		my $resolved_url = ($artworkurl =~ /^wavinshairport:image:/)
			? '/imageproxy/' . $artworkurl
			: $artworkurl;

		if ($resolved_url ne $oldartworkurl) {
			$oldartworkurl = $resolved_url;
			$icon = $resolved_url;
			Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
		}
		$icon = $resolved_url;
	}

	$log->debug("Source=$source artist=$artist title=$title");

	return {
		title   => $title,
		artist  => $artist,
		bitrate => "PCM",
		icon    => $icon,
		cover   => $icon,
		type    => $source,
	};

}


sub _getcover {
    my ( $url, $spec, $cb ) = @_;

    my $imagefilepath = File::Spec->catdir( '/tmp/wavinspotify', "cover.jpg" );

    $log->debug( "_getcover called for $imagefilepath" );

    return Slim::Utils::Misc::fileURLFromPath( $imagefilepath );
}

sub _getshairportcover {
    my ( $url, $spec, $cb ) = @_;

    my $imagefilepath = File::Spec->catdir( '/tmp/wavinshairport', "cover.jpg" );

    $log->debug( "_getshairportcover called for $imagefilepath" );

    return Slim::Utils::Misc::fileURLFromPath( $imagefilepath );
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
