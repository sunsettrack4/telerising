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

print "\n=============================================\n";
print   " TELERISING API v0.1.3 // ZATTOO SWITZERLAND \n";
print   "=============================================\n\n";

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
my $alias          = $analyse_login->{"session"}->{"aliased_country_code"};
my @products       = @{ $analyse_login->{"session"}->{"user"}->{"products"} };
my $powerid        = $analyse_login->{"session"}->{"power_guide_hash"};

my $product_code;

if( @products ) {
	foreach my $products ( @products) {
		if( $products->{"name"} =~ m/PREMIUM/ ) {
			$product_code = "PREMIUM";
		} elsif( $products->{"name"} =~ m/ULTIMATE/ ) {
			$product_code = "ULTIMATE";
		}
	}
}

if( defined $product_code ) {
	if( $product_code eq "PREMIUM" ) {
		print "--- YOUR ACCOUNT TYPE: PREMIUM ---\n\n"
	} elsif( $product_code eq "ULTIMATE" ) {
		print "--- YOUR ACCOUNT TYPE: ULTIMATE ---\n\n"
	}
} else {
	print "--- YOUR ACCOUNT TYPE: FREE ---\n\n";
	$product_code = "FREE";
}

if( $country ne "CH" ) {
	print "ERROR: Your German Zattoo account is not supported by this API.\n\n";
	exit;
}

my $tv_mode;

if( $alias ne "CH" and $product_code ne "FREE" ) {
	print "NOTICE: No Swiss IP address detected, using PVR mode for Live TV.\n\n";
	$tv_mode = "pvr";
} elsif ( $alias ne "CH" and $product_code eq "FREE" ) {
	print "ERROR: No Swiss IP address detected, Zattoo services can't be used.\n\n";
	exit;
} else {
	$tv_mode = "live";
}


#
# HTTP DAEMON PROCESS
#

# DEFINE PARAMS
my %O = (
    'clients' => 10,
    'max-req' => 100,
);
my $port = 8080;

# START DAEMON
my $d = HTTP::Daemon->new(
    LocalPort => $port,
    Reuse => 1,
	ReuseAddr => 1,
	ReusePort => $port,
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
		
		# SET DOLBY
		my $dolby = $params->{'dolby'};
		
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
		
		# SET AUDIO SEGMENT
		my $zaudio   = $params->{'audio'};
		
		
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
								$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
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
			
			if( $platform eq "hls" ) {
				
				#
				# HLS
				#
			
				my $time  = time()-24;
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
				
			} elsif( $platform eq "hls5" ) {
				
				#
				# HLS5
				# 
				
				my $time  = time()-24;
				my $check = $time/4;
				
				if( defined $zaudio ) {
					
					#
					# AUDIO
					#
					
					if( $check =~ m/\.75/ ) {
						
						my $utc = (($check*4000)-3000);
						my $stamp  = (($check*4000)-3000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						
						my $audiocodec;
						my $audiobw;
						my $audionum;
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						$zaudio =~ /(t_.*)(bw_.*)(num_.*)(\.m3u8)/m;
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
												
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n";

						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (1) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						
					} elsif( $check =~ m/\.5/ ) {
						
						my $utc = (($check*4000)-2000);
						my $stamp  = (($check*4000)-2000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $audiocodec;
						my $audiobw;
						my $audionum;
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						$zaudio =~ /(t_.*)(bw_.*)(num_.*)(\.m3u8)/m;
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
						
						my $audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (2) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						
					} elsif( $check =~ m/\.25/ ) {
						
						my $utc = (($check*4000)-1000);
						my $stamp  = (($check*4000)-1000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $audiocodec;
						my $audiobw;
						my $audionum;
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
						
						my $audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (3) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						
					} else {
						
						my $utc = ($check*4000);
						my $stamp  = ($check*4000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $audiocodec;
						my $audiobw;
						my $audionum;
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
												
						my $audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_4000_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (4) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
					
					}
				
				} else {
					
					#
					# VIDEO
					#
					
					if( $check =~ m/\.75/ ) {
						
						my $utc = (($check*4000)-3000);
						my $stamp  = (($check*4000)-3000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";

						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (1) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						
					} elsif( $check =~ m/\.5/ ) {
						
						my $utc = (($check*4000)-2000);
						my $stamp  = (($check*4000)-2000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (2) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						
					} elsif( $check =~ m/\.25/ ) {
						
						my $utc = (($check*4000)-1000);
						my $stamp  = (($check*4000)-1000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (3) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						
					} else {
						
						my $utc = ($check*4000);
						my $stamp  = ($check*4000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://fr5-0-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (4) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
					
					}
				
				}
			
			}
		
		#
		# PROVIDE CHANNEL M3U8
		#
		
		# CONDITION: HOME
		} elsif( defined $channel and defined $quality and defined $platform and $tv_mode eq "live" ) {
			
			# CHECK CONDITIONS
			if( $platform ne "hls" and  $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid platform\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid platform");
				$c->send_response($response);
				$c->close;
			
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "2999" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid bandwidth\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid bandwidth");
				$c->send_response($response);
				$c->close;
			
			} elsif( defined $channel ) {
				
				# REQUEST PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading Live URL\n";
				my $live_url = "https://zattoo.com/zapi/watch/live/$channel";
				
				my $live_agent = LWP::UserAgent->new;
				my $cookie_jar    = HTTP::Cookies->new;
				$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/','zattoo.com',443);
				$live_agent->cookie_jar($cookie_jar);

				my $live_request  = HTTP::Request::Common::POST($live_url, ['stream_type' => $platform, 'https_watch_urls' => 'True', 'enable_eac3' => 'true', 'timeshift' => '10800', 'cast_stream_type' => $platform ]);
				my $live_response = $live_agent->request($live_request);
				
				if( $live_response->is_error ) {
					
					# DO NOT PROCESS: WRONG CHANNEL ID
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid Channel ID\n";
					my $response = HTTP::Response->new( 400, 'BAD REQUEST');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Invalid Channel ID");
					$c->send_response($response);
					$c->close;
					
				} else {
					
					my $liveview_file = decode_json( $live_response->content );
					my $liveview_url = $liveview_file->{'stream'}->{'url'};
				
					# LOAD PLAYLIST URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading M3U8\n";
					my $livestream_agent  = LWP::UserAgent->new;
					
					my $livestream_request  = HTTP::Request::Common::GET($liveview_url);
					my $livestream_response = $livestream_agent->request($livestream_request);
					
					my $link  = $livestream_response->content;
					my $link2 = $livestream_response->content;
					my $uri   = $livestream_response->base;
					
					$uri     =~ s/(.*)(\/.*.m3u8.*)/$1/g;
					
					# EDIT PLAYLIST URL
					if( $platform eq "hls" ) {
						
						#
						# HLS
						#
						
						# SET FINAL QUALITY
						my $final_quality;
						
						if( $link =~ m/BANDWIDTH=8000000/ and $quality eq "8000" ) {
							$final_quality = "8000";
						} elsif( $link =~ m/BANDWIDTH=5000000/ and $quality eq "8000" ) {
							$final_quality = "5000";
						} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "8000" ) {
							$final_quality = "2999";
						} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "8000" ) {
							$final_quality = "1500";
						} elsif( $link =~ m/BANDWIDTH=4999000/ and $quality eq "4999" ) {
							$final_quality = "4999";
						} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "4999" ) {
							$final_quality = "2999";
						} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "4999" ) {
							$final_quality = "1500";
						} elsif( $link =~ m/BANDWIDTH=5000000/ and $quality eq "5000" ) {
							$final_quality = "5000";
						} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "5000" ) {
							$final_quality = "2999";
						} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "5000" ) {
							$final_quality = "1500";
						} elsif( $link =~ m/BANDWIDTH=3000000/ and $quality eq "3000" ) {
							$final_quality = "3000";
						} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "3000" ) {
							$final_quality = "2999";
						} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "3000" ) {
							$final_quality = "1500";
						} elsif( $link =~ m/BANDWIDTH=3000000/ and $quality eq "2999" ) {
							$final_quality = "3000";
						} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "2999" ) {
							$final_quality = "2999";
						} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "2999" ) {
							$final_quality = "1500";
						} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "1500" ) {
							$final_quality = "1500";
						}
						
						# EDIT PLAYLIST
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing M3U8\n";
						$link        =~ /(.*live-$final_quality.*)/m;
						my $link_url = $uri . "/" . $1; 
						
						my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=" . $final_quality . "000\n" . $link_url;
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text/html'),
						$response->content($m3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
					
					} elsif( $platform eq "hls5" ) {
						
						#
						# HLS5
						#
						
						# SET FINAL VIDEO PARAMS
						my $final_quality_video;
						my $final_bandwidth;
						my $final_resolution;
						my $final_framerate;
						
						if( $quality eq "8000" ) {
							$final_quality_video = "7800";
							$final_bandwidth  = "8000000";
							$final_resolution = "1920x1080";
							$final_framerate  = "50";
						} elsif( $quality eq "4999" ) {
							$final_quality_video = "4799";
							$final_bandwidth  = "5000000";
							$final_resolution = "1280x720";
							$final_framerate  = "50";
						} elsif( $quality eq "5000" ) {
							$final_quality_video = "4800";
							$final_bandwidth  = "4999000";
							$final_resolution = "1920x1080";
							$final_framerate  = "25";
						} elsif( $quality eq "3000" ) {
							$final_quality_video = "2800";
							$final_bandwidth  = "3000000";
							$final_resolution = "1280x720";
							$final_framerate  = "25";
						} elsif( $quality eq "2999" ) {
							$final_quality_video = "2799";
							$final_bandwidth  = "2999000";
							$final_resolution = "1024x576";
							$final_framerate  = "50";
						} elsif( $quality eq "1500" ) {
							$final_quality_video = "1300";
							$final_bandwidth  = "1500000";
							$final_resolution = "768x432";
							$final_framerate  = "25";
						}
						
						# SET FINAL AUDIO CODEC
						my $final_quality_audio;
						my $final_codec;
						
						if( defined $dolby ) {
							if( $link =~ m/t_track_audio_bw_256_num_1/ and $dolby eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3";
							} else {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							}
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
						
						# EDIT PLAYLIST
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing M3U8\n";
						$link        =~ /(.*)($final_quality_audio.*?z32=)(.*)"/m;
						my $link_video_url = $uri . "/" . "t_track_video_bw_$final_quality_video" . "_num_0.m3u8?z32=" . $3;
						my $link_audio_url = $uri . "/" . $2 . $3;
						
						my $m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"Default\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"mis\",URI=\"$link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text/html'),
						$response->content($m3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
						
					}
				
				}
			
			}
			
		# CONDITION: WORLDWIDE
		} elsif( defined $channel and defined $quality and defined $platform and $tv_mode eq "pvr" ) {
			
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
				
				# DO NOT PROCESS: WRONG CHANNEL ID / NO EPG AVAILABLE
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid channel ID / no EPG available\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid Channel ID");
				$c->send_response($response);
				$c->close;
				
			} elsif( $platform ne "hls" and  $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid platform\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid platform");
				$c->send_response($response);
				$c->close;
			
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "2999" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Invalid bandwidth\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid bandwidth");
				$c->send_response($response);
				$c->close;
			
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

				my $recview_request  = HTTP::Request::Common::POST($recview_url, ['stream_type' => $platform, 'enable_eac3' => 'true', 'https_watch_urls' => 'True', 'cast_stream_type' => $platform ]);
				my $recview_response = $recview_agent->request($recview_request);
				
				my $recview_file = decode_json( $recview_response->content );
				my $rec_url = $recview_file->{'stream'}->{'url'};
				
				# LOAD PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading M3U8\n";
				my $recurl_agent  = LWP::UserAgent->new;
				
				my $recurl_request  = HTTP::Request::Common::GET($rec_url);
				my $recurl_response = $recurl_agent->request($recurl_request);
				
				my $link = $recurl_response->content;
				my $uri  = $recurl_response->base;
				my $ch   = $recurl_response->base;

				$uri     =~ s/(.*)(\/.*.m3u8.*)/$1/g;
				$ch      =~ s/.*\.tv\///g;
				$ch      =~ s/https:\/\/zattoo-$platform-pvr.akamaized.net\///g;
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
				if( $platform eq "hls" ) {
					
					#
					# HLS
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					
					my $final_quality;
					
					if( $link =~ m/BANDWIDTH=8000000/ and $quality eq "8000" ) {
						$final_quality = "8000";
					} elsif( $link =~ m/BANDWIDTH=5000000/ and $quality eq "8000" ) {
						$final_quality = "5000";
					} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "8000" ) {
						$final_quality = "2999";
					} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "8000" ) {
						$final_quality = "1500";
					} elsif( $link =~ m/BANDWIDTH=4999000/ and $quality eq "4999" ) {
						$final_quality = "4999";
					} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "4999" ) {
						$final_quality = "2999";
					} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "4999" ) {
						$final_quality = "1500";
					} elsif( $link =~ m/BANDWIDTH=5000000/ and $quality eq "5000" ) {
						$final_quality = "5000";
					} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "5000" ) {
						$final_quality = "2999";
					} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "5000" ) {
						$final_quality = "1500";
					} elsif( $link =~ m/BANDWIDTH=3000000/ and $quality eq "3000" ) {
						$final_quality = "3000";
					} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "3000" ) {
						$final_quality = "2999";
					} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "3000" ) {
						$final_quality = "1500";
					} elsif( $link =~ m/BANDWIDTH=3000000/ and $quality eq "2999" ) {
						$final_quality = "3000";
					} elsif( $link =~ m/BANDWIDTH=2999000/ and $quality eq "2999" ) {
						$final_quality = "2999";
					} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "2999" ) {
						$final_quality = "1500";
					} elsif( $link =~ m/BANDWIDTH=1500000/ and $quality eq "1500" ) {
						$final_quality = "1500";
					}
					
					$link        =~ /(.*$final_quality.m3u8.*)/m;
					my $link_url = $uri . "/" . $1; 
					
					# LOAD SEGMENTS URL
					my $link_agent  = LWP::UserAgent->new;
				
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
					
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/$final_quality.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /($final_quality\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=$final_quality" . "000\n" . "http://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality\&platform=hls\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";
				
				} elsif( $platform eq "hls5" ) {
					
					#
					# HLS5
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Loading segments file\n";
					
					# SET FINAL VIDEO PARAMS
					my $final_quality_video;
					my $final_bandwidth;
					my $final_resolution;
					my $final_framerate;
						
					if( $quality eq "8000" ) {
						$final_quality_video = "7800";
						$final_bandwidth  = "8000000";
						$final_resolution = "1920x1080";
						$final_framerate  = "50";
					} elsif( $quality eq "4999" ) {
						$final_quality_video = "4799";
						$final_bandwidth  = "5000000";
						$final_resolution = "1280x720";
						$final_framerate  = "50";
					} elsif( $quality eq "5000" ) {
						$final_quality_video = "4800";
						$final_bandwidth  = "4999000";
						$final_resolution = "1920x1080";
						$final_framerate  = "25";
					} elsif( $quality eq "3000" ) {
						$final_quality_video = "2800";
						$final_bandwidth  = "3000000";
						$final_resolution = "1280x720";
						$final_framerate  = "25";
					} elsif( $quality eq "2999" ) {
						$final_quality_video = "2799";
						$final_bandwidth  = "2999000";
						$final_resolution = "1024x576";
						$final_framerate  = "50";
					} elsif( $quality eq "1500" ) {
						$final_quality_video = "1300";
						$final_bandwidth  = "1500000";
						$final_resolution = "768x432";
						$final_framerate  = "25";
					}
					
					# SET FINAL AUDIO CODEC
					my $final_quality_audio;
					my $final_codec;
						
					if( defined $dolby ) {
						if( $link =~ m/t_track_audio_bw_256_num_1/ and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3";
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
					} else {
						$final_quality_audio = "t_track_audio_bw_128_num_0";
						$final_codec = "avc1.4d4020,mp4a.40.2";
					}
					
					# EDIT PLAYLIST
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing M3U8\n";
					
					$uri         =~ s/.*\.tv\///g;
					$uri         =~ s/.*\.net\///g;
					$uri         =~ /(.*)\/(.*)\/(.*)/m;
					
					my $ch          = $1;
					my $start       = $2;
					my $end         = $3;
					
					$link        =~ /(.*)($final_quality_audio.*)(\?z32=)(.*)"/m;
					
					my $audio    = $2;
					my $keyval   = $4;
					
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"Default\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"mis\",URI=\"http://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality_video\&audio=$audio\&platform=hls5\&zkey=$keyval\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\nhttp://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality_video\&platform=hls5\&zkey=$keyval";
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
					
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "$channel | $quality | $platform - Playlist sent to client\n";	
					
				}			
					
			}			
		
		#
		# INVALID REQUEST
		#
		
		} else {
			
			print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Invalid request by client\n";
			my $response = HTTP::Response->new( 400, 'BAD REQUEST');
			$response->header('Content-Type' => 'text/html'),
			$response->content("API ERROR: Invalid request by client\n");
			$c->send_response($response);
			$c->close;
		}
	}
}
