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

my $oldartworkurl = '';

sub isRemote { 1 }

sub bufferThreshold { 100 }

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

	if ( CAN_IMAGEPROXY ) {
		require Slim::Web::ImageProxy;
		Slim::Web::ImageProxy->import();
		Slim::Web::ImageProxy->registerHandler(
			match => qr/wavinspotify:image:/,
			func  => \&_getcover,
		);
	}
	else {
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


	my $filename = '/tmp/wavinspotify/spotifymetadata';
	open(my $fh, '<:encoding(UTF-8)', $filename)
		or die "Could not open file '$filename' $!";

	my $counter = 0;
	my $artist = '';
	my $title = '';
	my $artworkurl = '';

	while (my $row = <$fh>) {
		chomp $row;
	#  print "$counter: $row\n";
		if($counter == 0){ $artist = $row; }
		if($counter == 1){ $title = $row; }
		if($counter == 2){ $artworkurl = $row; }
		$counter=$counter+1;
	}

	#log->error("Cache: $cachedir");
	if ($artworkurl ne "")
	{
		if ($artworkurl ne $oldartworkurl){
			#my $imagefilepath = File::Spec->catdir( $cachedir, 'wavinspotify', "cover.jpg" );
			#my $wgetout = `wget -q $artworkurl -O $imagefilepath`;
			#log->error("cachedir: $cachedir   artwork: $artworkurl");
			#my $imageurl      = "/imageproxy/wavinspotify:image:/cover.jpg";
			$oldartworkurl = $artworkurl;
			$icon = $artworkurl;
			Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
		}
		$icon = $artworkurl; #"/imageproxy/wavinspotify:image:/cover.jpg"; #$oldartworkurl;
	}

	#$log->error("Coverurl: $icon");

#       Slim::Music::Info::setCurrentTitle( $url, 'PC WaveInput'  );
	return {
#       title    =>  'WaveInput',
		title    =>  $title,
		artist   =>  $artist,
		bitrate  =>  "PCM",
		icon   => $icon,
		cover  => $icon,
		type   => 'Spotify',
	};

}


sub _getcover {
    my ( $url, $spec, $cb ) = @_;

    # $url is aforementioned image URL
    # $spec we don't need (yet)
    # $cb is the callback to be called with the URL

    #my ( $track_id ) = $url =~ m|shairtunes:image:(.*?)$|i;

    my $imagefilepath = File::Spec->catdir( '/tmp/wavinspotify', "cover.jpg" );

    $log->error( "_getcover called for $imagefilepath" );

    # now return the URLified file path
    return Slim::Utils::Misc::fileURLFromPath( $imagefilepath );
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
