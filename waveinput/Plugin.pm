#
# A plugin to enable WaveInput to be played using Alsa 
#

use strict;

package Plugins::WaveInput::Plugin;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::WaveInput::Settings;

use Plugins::WaveInput::WAVIN;


# create log categogy before loading other modules
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.waveinput',
	'defaultLevel' => 'ERROR',
#	'defaultLevel' => 'INFO',
	'description'  => getDisplayName(),
});


use Slim::Utils::Misc;
my $prefs       = preferences('plugin.waveinput');



################################
### Plugin Interface ###########
################################


sub initPlugin 
{
	my $class = shift;

	$log->info("Initialising " . $class->_pluginDataFor('version'));
	Plugins::WaveInput::Settings->new($class);
	Plugins::WaveInput::Settings->init();


#	Slim::Control::Request::subscribe( \&pauseCallback, [['pause']] );

	return 1;
}

sub pauseCallback {
	my $request = shift;
	my $client  = $request->client;

	my $stream  = Slim::Player::Playlist::song($client)->path;
	my $playmode= Slim::Player::Source::playmode($client);
	my $mode    = Slim::Buttons::Common::mode($client);

	$log->debug("cli Pause - playmode=$playmode  stream=$stream ");

	if ($stream =~ /^wavin:/ ) {
#	if ($playmode eq 'pause' && $stream =~ /^wavin:/ ) {
		if ($prefs->get('pausestop')) {
			$log->debug("Issuing stop");
			$client->execute([ 'stop' ]);
		}
	}

}


sub shutdownPlugin 
{
#	Slim::Control::Request::unsubscribe(\&pauseCallback);
 	return;
}

sub getDisplayName() 
{ 
	return('PLUGIN_WAVEINPUT')
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
