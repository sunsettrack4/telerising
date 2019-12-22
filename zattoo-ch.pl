#!/usr/bin/perl

#      Copyright (C) 2019 Jan-Luca Neumann
#      https://github.com/sunsettrack4/telerising/
#
#  This Program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3, or (at your option)
#  any later version.
#
#  This Program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with zattoo_tvh. If not, see <http://www.gnu.org/licenses/>.

# #######################################
# TELERISING API FOR ZATTOO SWITZERLAND #
# #######################################

print "=============================================\n";
print " TELERISING API v0.1.0 // ZATTOO SWITZERLAND \n";
print "=============================================\n\n";

use strict;
use warnings;

binmode STDOUT, ":utf8";
use utf8;

use LWP;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Daemon;
use HTTP::Request::Params;
use HTTP::Request::Common qw{ POST };
use HTTP::Request::Params;
use HTTP::Cookies;
use HTML::TreeBuilder;
use URI::Escape;
use Time::Piece;
use Sys::HostIP;
use JSON;
use POSIX qw/ WNOHANG /;


#
# LOGIN PROCESS
#

# READ USERFILE
my $json;
{
    local $/; #Enable 'slurp' mode
    open my $fh, "<", "userfile.json" or die "UNABLE TO LOGIN TO WEBSERVICE! (User data can't be found!)\n\n";
    $json = <$fh>;
    close $fh;
}

# SET LOGIN PARAMS
my $userfile     = decode_json($json);
my $login_mail   = $userfile->{'login'};
my $login_passwd = $userfile->{'password'};

# GET APPTOKEN
my $main_url     = "https://zattoo.com/";
my $main_req     = get($main_url);
my $parser       = HTML::Parser->new;

if( not defined $main_req) {
	print "UNABLE TO LOGIN TO WEBSERVICE! (no internet connection / service unavailable)\n\n";
	exit;
}

my $zattootree   = HTML::TreeBuilder->new;
$zattootree->parse($main_req);

my @scriptvalues = $zattootree->look_down('type' => 'text/javascript');
my $apptoken     = $scriptvalues[0]->as_HTML;
$apptoken        =~ s/(.*window.appToken = ')(.*)(';.*)/$2/g;

# GET SESSION ID
my $session_url    = "https://zattoo.com/zapi/session/hello";
my $session_agent  = LWP::UserAgent->new;

my $session_request  = HTTP::Request::Common::POST($session_url, ['client_app_token' => uri_escape($apptoken), 'uuid' => uri_escape('d7512e98-38a0-4f01-b820-5a5cf98141fe'), 'lang' => uri_escape('en'), 'format' => uri_escape('json')]);
my $session_response = $session_agent->request($session_request);
my $session_token    = $session_response->header('Set-cookie');
$session_token       =~ s/(.*)(beaker.session.id=)(.*)(; Path.*)/$3/g;

if( $session_response->is_error ) {
	print "LOGIN FAILED! (invalid response)\n\n";
	exit;
}

# GET LOGIN COOKIE
my $login_url    = "https://zattoo.com/zapi/v2/account/login";
my $login_agent   = LWP::UserAgent->new;
my $cookie_jar    = HTTP::Cookies->new;
$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/','zattoo.com',443);
$login_agent->cookie_jar($cookie_jar);

my $login_request  = HTTP::Request::Common::POST($login_url, ['login' => $login_mail, 'password' => $login_passwd ]);
my $login_response = $login_agent->request($login_request);

if( $login_response->is_error ) {
	print "LOGIN FAILED! (please re-check login data)\n\n";
	exit;
} else {
	print "LOGIN OK!\n\n";
}

my $login_token    = $login_response->header('Set-cookie');
$login_token       =~ s/(.*)(beaker.session.id=)(.*)(; Path.*)/$3/g;

# ANALYSE ACCOUNT
my $analyse_login  = decode_json($login_response->content);
my $country        = $analyse_login->{"session"}->{"service_region_country"};
my @products       = @{ $analyse_login->{"session"}->{"user"}->{"products"} };
my $powerid        = $analyse_login->{"session"}->{"power_guide_hash"};

if( $country ne "CH" ) {
	print "ERROR: Your German Zattoo account is not supported by this API.\n";
	exit;
}

if( @products ) {
	print "------------------------------\n";
	print "PRODUCTS: \n";
	foreach my $products ( @products) {
		print "* " . $products->{"name"} . "\n";
	}
	print "------------------------------\n\n";
}


#
# HTTP DAEMON PROCESS
#

# DEFINE PARAMS
my %O = (
    'port' => 8080,
    'clients' => 10,
    'max-req' => 100,
);

# START DAEMON
my $d = HTTP::Daemon->new(
    LocalPort => $O{'port'},
    Reuse => 1,
	ReuseAddr => 1,
	ReusePort => $O{'port'},
) or die "API CANNOT BE STARTED!\n\n";

my $hostipchecker = Sys::HostIP->new;
my $hostip = $hostipchecker->ip;

print "API STARTED!\n\n";

#
my %chld;

if ($O{'clients'}) {
    $SIG{CHLD} = sub {
        while ((my $kid = waitpid(-1, WNOHANG)) > 0) {
            delete $chld{$kid};
        }
    };
}

while (1) {
    if ($O{'clients'}) {
        # PREFORK PROCESS
        for (scalar(keys %chld) .. $O{'clients'} - 1 ) {
            my $pid = fork;

            if (!defined $pid) { # ERROR
                die "PREFORK PROCESS FAILED FOR HTTP CHILD $_: $!";
            }
            if ($pid) { # PARENT
                $chld{$pid} = 1;
            }
            else { # CHILD
                $_ = 'DEFAULT' for @SIG{qw/ INT TERM CHLD /};
                http_child($d);
                exit;
            }
        }
    }
    else {
        http_child($d);
    }

}

# ACCEPT REQUEST
sub http_child {
    my $d = shift;

    my $i;

    while (++$i < $O{'max-req'}) {
        my $c = $d->accept or last;
        my $request = $c->get_request(1) or last;
        $c->autoflush(1);
				
		# READ QUERY STRING PARAMS
		my $parse_params = HTTP::Request::Params->new({
							 req => $request,
						   });
		my $params       = $parse_params->params;
		
		# GET CHANNEL NAME
		my $channel = $params->{'channel'};
		my $zch     = $params->{'ch'};
		
		# SET QUALITY
		my $quality = $params->{'bw'};
		
		# SET PLATFORM
		my $platform = $params->{'platform'};
		
		# SET FILE
		my $filename = $params->{'file'};
		
		# SET KEYVALUE
		my $zkeyval  = $params->{'zkey'};
		
		# SET START
		my $zstart   = $params->{'start'};
		
		# SET END
		my $zend     = $params->{'end'};
		
		# SET REC ID
		my $zid      = $params->{'zid'};
		
		# KILLSWITCH
		my $apikill  = $params->{'apikill'};
		
		
		
		#
		# RETRIEVE FILES
		#
		
		if( defined $filename and defined $quality and defined $platform ) {
			
			# GET CHANNEL LIST
			if( 
				$filename eq "channels.m3u" and 
				
				$quality eq "8000" or 
				$quality eq "5000" or 
				$quality eq "4999" or 
				$quality eq "3000" or 
				$quality eq "1500" and 
				
				$platform eq "hls" or 
				$platform eq "hls5" ) {
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Loading channels.m3u... \n";
				
				my $channel_url   = "https://zattoo.com/zapi/v2/cached/channels/$powerid?details=False";
				my $channel_agent = LWP::UserAgent->new;
				my $cookie_jar    = HTTP::Cookies->new;
				$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/','zattoo.com',443);
				$channel_agent->cookie_jar($cookie_jar);

				my $channel_request  = HTTP::Request::Common::GET($channel_url);
				my $channel_response = $channel_agent->request($channel_request);
				
				# READ JSON
				my $ch_file = decode_json($channel_response->content);

				# SET UP VALUES
				my @ch_groups = @{ $ch_file->{'channel_groups'} };
				
				my $ch_m3u   = "#EXTM3U\n";
				
				foreach my $ch_groups ( @ch_groups ) {
					my @channels = @{ $ch_groups->{'channels'} };
					my $group    = $ch_groups->{'name'};
					
					
					foreach my $channels ( @channels ) {
						my $name    = $channels->{'title'};
						my $service = $channels->{'title'} =~ s/\//\\\\\//g;
						my $chid    = $channels->{'cid'};
						my $alias   = $channels->{'display_alias'};
						
						# IF FIRST CHANNEL TYPE IS "AVAILABLE", PRINT M3U LINE
						if( defined $channels->{'qualities'}[0]{'availability'} ) {
							if( $channels->{'qualities'}[0]{'availability'} eq "available" ) {
								my $logo = $channels->{'qualities'}[0]{'logo_black_84'};
								$logo =~ s/84x48.png/210x120.png/g;
								
								$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $chid . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
								$ch_m3u = $ch_m3u .  "http://$hostip:8080/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
							}
						}
					}
				}
				
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'application/vnd.apple.mpegurl'),
				$response->content($ch_m3u);
				$c->send_response($response);
				$c->close;
				
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Channel list sent to client - params: bandwidth=$quality, platform=$platform\n";
			}
		
		#
		# PROVIDE SEGMENTS M3U8
		#
		
		} elsif( defined $zch and defined $zstart and defined $zend and defined $zkeyval and defined $quality and defined $platform ) {
			
			my $time  = time()-20;
			my $check = $time/4;
			
			if( defined $time ) {
				
				if( $check =~ m/\.75/ ) {
					my $stamp  = $check*4-3;
					my $stamp2 = $stamp+4;
					my $stamp3 = $stamp+8;
					my $seq   = $stamp/4;
					my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
					
					my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval";

					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text'),
					$response->content($videom3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (1) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
					
				} elsif( $check =~ m/\.5/ ) {
					
					my $stamp = $check*4-2;
					my $stamp2 = $stamp+4;
					my $stamp3 = $stamp+8;
					my $seq   = $stamp/4;
					my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
					
					my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text'),
					$response->content($videom3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (2) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
					
				} elsif( $check =~ m/\.25/ ) {
					
					my $stamp = $check*4-1;
					my $stamp2 = $stamp+4;
					my $stamp3 = $stamp+8;
					my $seq   = $stamp/4;
					my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
					
					my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text'),
					$response->content($videom3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (3) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
					
				} else {
					
					my $stamp = $check*4;
					my $stamp2 = $stamp+4;
					my $stamp3 = $stamp+8;
					my $seq   = $stamp/4;
					my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
					
					my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text'),
					$response->content($videom3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (4) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
				}
			}
			
		
		#
		# PROVIDE CHANNEL M3U8
		#
		
		# CONDITION: WORLDWIDE
		} elsif( defined $channel and defined $quality and defined $platform ) {
			
			# LOAD EPG
			print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Requesting current EPG\n";
			my $start   = time();
			my $stop    = time()+1;
			my $epg_url = "https://zattoo.com/zapi/v3/cached/$powerid/guide?start=$start&end=$stop";
			
			my $epg_agent = LWP::UserAgent->new;
			my $cookie_jar    = HTTP::Cookies->new;
			$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/','zattoo.com',443);
			$epg_agent->cookie_jar($cookie_jar);

			my $epg_request  = HTTP::Request::Common::GET($epg_url);
			my $epg_response = $epg_agent->request($epg_request);
				
			# READ JSON
			my $epg_file = decode_json($epg_response->content);
			my $rec_id   = $epg_file->{'channels'}{$channel}[0]{'id'};
			
			# CHECK CONDITIONS
			if( not defined $rec_id ) {
				
				# DO NOT PROCESS: WRONG CHANNEL ID
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid channel ID\n";
				
			} elsif( $platform ne "hls" and  $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid platform\n";
			
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid bandwidth\n";
			
			} elsif( defined $channel ) {
			
				# ADD RECORDING
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Add recording\n";
				my $recadd_url = "https://zattoo.com/zapi/playlist/program";
				
				my $recadd_agent  = LWP::UserAgent->new;
				$recadd_agent->cookie_jar($cookie_jar);

				my $recadd_request  = HTTP::Request::Common::POST($recadd_url, ['program_id' => $rec_id, 'series' => 'false', 'series_force' => 'false' ]);
				my $recadd_response = $recadd_agent->request($recadd_request);
				
				my $rec_file = decode_json( $recadd_response->content );
				my $rec_fid  = $rec_file->{"recording"}->{"id"};
				
				# LOAD RECORDING URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading PVR URL\n";
				my $recview_url = "https://zattoo.com/zapi/watch/recording/$rec_fid";
				
				my $recview_agent  = LWP::UserAgent->new;
				$recview_agent->cookie_jar($cookie_jar);

				my $recview_request  = HTTP::Request::Common::POST($recview_url, ['stream_type' => $platform, 'https_watch_urls' => 'True', 'cast_stream_type' => $platform ]);
				my $recview_response = $recview_agent->request($recview_request);
				
				my $recview_file = decode_json( $recview_response->content );
				my $rec_url = $recview_file->{'stream'}->{'cast_url'};
				
				# LOAD PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading M3U8\n";
				my $recurl_agent  = LWP::UserAgent->new;
				
				my $recurl_request  = HTTP::Request::Common::GET($rec_url);
				my $recurl_response = $recurl_agent->request($recurl_request);
				
				my $link = $recurl_response->content;
				my $uri  = $recurl_response->base;
				my $ch   = $recurl_response->base;
				$uri     =~ s/(.*)(\/.*.m3u8.*)/$1/g;
				$ch      =~ s/.*.tv\///g;
				$ch      =~ s/\/.*//g;
				
				# REMOVE RECORDING
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Remove recording\n";
				my $recdel_url = "https://zattoo.com/zapi/playlist/remove";
				
				my $recdel_agent  = LWP::UserAgent->new;
				$recdel_agent->cookie_jar($cookie_jar);

				my $recdel_request  = HTTP::Request::Common::POST($recdel_url, ['recording_id' => $rec_fid ]);
				my $recdel_response = $recdel_agent->request($recdel_request);
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Recording removed\n";
				
				# EDIT PLAYLIST URL
				if( $platform eq "hls" and $quality eq "8000" and $link =~ m/BANDWIDTH=8000000/ ) {
					
					#
					# HLS 8000 ~ 8000 1080p50 ULTIMATE
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*8000.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/8000.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(8000\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=8000000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=8000&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "8000" and $link =~ m/BANDWIDTH=2999000/ ) {
					
					#
					# HLS 8000 ~ 2999 576p50 ULTIMATE
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*2999.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/2999.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(2999\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2999000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=2999&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "5000" and $link =~ m/BANDWIDTH=5000000/ ) {
					
					#
					# HLS 5000 ~ 5000 720p50 PREMIUM
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*5000.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/5000.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(5000\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=5000000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=5000&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "5000" and $link =~ m/BANDWIDTH=2999000/ ) {
					
					#
					# HLS 5000 ~ 2999 576p50 PREMIUM
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*2999.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/2999.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(2999\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2999000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=2999&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "4999" and $link =~ m/BANDWIDTH=4999000/ ) {
					
					#
					# HLS 4999 ~ 4999 1080p25 ULTIMATE
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*4999.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/4999.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(4999\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=4999000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=4999&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "4999" and $link =~ m/BANDWIDTH=2999000/ ) {
					
					#
					# HLS 4999 ~ 2999 576p50 ULTIMATE
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*2999.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/2999.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(2999\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2999000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=2999&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "3000" and $link =~ m/BANDWIDTH=3000000/ ) {
					
					#
					# HLS 3000 ~ 3000 720p25 PREMIUM
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*3000.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/3000.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(3000\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=3000000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=3000&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "3000" and $link =~ m/BANDWIDTH=2999000/ ) {
					
					#
					# HLS 3000 ~ 2999 576p50 PREMIUM
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*2999.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/2999.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(2999\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2999000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=2999&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls" and $quality eq "1500" and $link =~ m/BANDWIDTH=1500000/ ) {
					
					#
					# HLS 1500 ~ 1500 432p25 FREE
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					$link        =~ /(.*1500.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/1500.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /(1500\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1500000\n" . "http://$hostip:8080/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=1500&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
					
				}
			
			} else {
				
				# DO NOT PROCESS: WRONG CONDITIONS
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Invalid channel request by client\n";
				my $response = HTTP::Response->new( 404, 'NOT FOUND');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid channel request");
				$c->send_response($response);
				$c->close;
			}
			
		
		#
		# KILL SWITCH
		#
		
		} elsif( defined $apikill ) {
			
			print "C " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Kill request sent by client\n";
			print "\n--- STOPPING API SERVICE ---\n\n";
			exit;
		
		
		#
		# INVALID REQUEST
		#
		
		} else {
			
			print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Invalid request by client\n";
			my $response = HTTP::Response->new( 404, 'NOT FOUND');
			$response->header('Content-Type' => 'text/html'),
			$response->content("API ERROR: Invalid request by client\n");
			$c->send_response($response);
			$c->close;
		}
	}
}
