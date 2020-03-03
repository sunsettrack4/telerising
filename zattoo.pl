#!/usr/bin/perl

#      Copyright (C) 2019-2020 Jan-Luca Neumann
#      https://github.com/sunsettrack4/telerising/
#
#      Collaborators:
#      - DeBaschdi ( https://github.com/DeBaschdi )
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
#  along with telerising. If not, see <http://www.gnu.org/licenses/>.

# ####################################
# TELERISING API FOR ZATTOO + WILMAA #
# ####################################

unlink "log.txt";
unlink "error.txt";


use IO::Tee;
my $tee = new IO::Tee(\*STDOUT, ">>log.txt");
select $tee;

print "\n=======================\n";
print   " TELERISING API v0.3.1 \n";
print   "=======================\n\n";

print "(c) 2019-2020 Jan-Luca Neumann (sunsettrack4)\n";
print "Please donate to support my work: https://paypal.me/sunsettrack4\n\n";


use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($INFO);

my $logConfiguration = qq(
log4perl.logger        = INFO, Logfile, Screen
log4perl.appender.Logfile          =  Log::Log4perl::Appender::File
log4perl.appender.Logfile.filename = log.txt
log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
log4perl.appender.Logfile.layout.ConversionPattern =%p[%d{MM/dd HH:mm} %3L] %m%n
log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
log4perl.appender.Screen.stderr  = 0
log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout
log4perl.appender.Screen.layout.ConversionPattern = %m%n
);

Log::Log4perl::init( \$logConfiguration );

use strict;
use warnings;

binmode STDOUT, ":utf8";
use utf8;

use LWP;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Request::Params;
use HTTP::Request::Common;
use HTTP::Cookies;
use HTML::TreeBuilder;
use URI::Escape;
use Time::Piece;
use IO::Interface::Simple;
use IO::Socket::SSL;
use Mozilla::CA; 
use JSON;
use Encode;
use POSIX qw/ WNOHANG /;
use POSIX qw( strftime );


#
# LOGIN PROCESS
#

sub login_process {
	my $login;
	
	unless( $login = fork() ) {
		
		while(1) {
			# READ USERFILE
			my $json;
			{
				local $/; #Enable 'slurp' mode
				open my $fh, "<", "userfile.json" or die "UNABLE TO LOGIN TO WEBSERVICE! (User data can't be found!)\n\n";
				$json = <$fh>;
				close $fh;
			}

			# SET LOGIN PARAMS
			my $userfile;
			
			eval{
				$userfile     = decode_json($json);
			};
			
			if( not defined $userfile ) {
				ERROR "ERROR: Unable to parse user data\n\n";
				open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
				print $error_file "ERROR: Unable to parse user data";
				close $error_file;
				exit;
			}
			
			my $provider     = $userfile->{'provider'};
			my $login_mail   = $userfile->{'login'};
			my $login_passwd = $userfile->{'password'};
			my $interface    = $userfile->{'interface'};
			my $customip     = $userfile->{'address'};
			my $zserver      = $userfile->{'server'};
			my $ffmpeglib    = $userfile->{'ffmpeg_lib'};
			my $port         = $userfile->{'port'};
			my $pin          = $userfile->{'youth_protection_pin'};
			my $ssl_mode     = $userfile->{'ssl_mode'};
			my $ssl_verify;
			
			if( not defined $provider ) {
				ERROR "ERROR: No provider selected\n\n";
				open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
				print $error_file "ERROR: No provider selected";
				close $error_file;
				exit;
			} elsif( $provider ne "wilmaa.com" ) {
				if( not defined $login_mail or not defined $login_passwd ) {
					ERROR "ERROR: Unable to retrieve complete login data\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: Unable to retrieve complete login data";
					close $error_file;
					exit;
				}
			} elsif( $provider eq "wilmaa.com" ) {
				if( not defined $login_mail and defined $login_passwd ) {
					ERROR "ERROR: Unable to retrieve complete login data\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: Unable to retrieve complete login data";
					close $error_file;
					exit;
				} elsif( defined $login_mail and not defined $login_passwd ) {
					ERROR "ERROR: Unable to retrieve complete login data\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: Unable to retrieve complete login data";
					close $error_file;
					exit;
				}
			}
			
			# SET DEFAULT VALUES
			if( not defined $interface and not defined $customip ) {
				$interface = "";
				$customip  = "";
			} elsif( defined $customip ) {
				if( $customip ne "" ) {
					$interface = "";
					INFO "Custom IP address or domain \"$customip\" will be used.\n\n";
				} elsif( defined $interface ) {
					if( $interface ne "" ) {
						$customip = "";
						INFO "Custom interface \"$interface\" will be used.\n\n";
					} else {
						$customip  = "";
						$interface = "";
					}
				} else {
					$customip  = "";
					$interface = "";
				}
			} elsif( defined $interface ) {
				if( $interface ne "" ) {
					$customip = "";
					INFO "Custom interface \"$interface\" will be used.\n\n";
				} else {
					$customip  = "";
					$interface = "";
				}
			}
			
			if( not defined $zserver ) {
				$zserver = "fr5-0";
			} elsif( $zserver eq "" ) {
				$zserver = "fr5-0";
			} elsif( $zserver =~ /fr5-[0-5]|fra3-[0-3]|zh2-[0-9]|zba6-[0-2]|1und1-fra1902-[1-4]|1und1-hhb1000-[1-4]|1und1-dus1901-[1-4]|1und1-ess1901-[1-2]|matterlau1-[0-1]|matterzrh1-[0-1]/ ) {
				INFO "Custom Zattoo server \"$zserver\" will be used.\n\n";
			} else {
				INFO "Custom Zattoo server \"$zserver\" is not supported, default server will be used instead.\n\n";
				$zserver = "fr5-0";
			}
			
			if( not defined $ffmpeglib ) {
				$ffmpeglib = "/usr/bin/ffmpeg";
			} elsif( $ffmpeglib eq "" ) {
				$ffmpeglib = "/usr/bin/ffmpeg";
			} elsif( $ffmpeglib =~ /\/usr\/bin\/ffmpeg|\/bin\/ffmpeg|\/ramdisk\/ffmpeg/ ) {
				INFO "Use custom ffmpeg library path \"$ffmpeglib\"\n\n";
			} else {
				INFO "ffmpeg library path \"$ffmpeglib\" is not supported, default library will be used instead.\n\n";
				$ffmpeglib = "/usr/bin/ffmpeg";
			}
			
			if( not defined $port ) {
				$port = "8080";
			} elsif( $port eq "" ) {
				$port = "8080";
			} else {
				INFO "Custom port \"$port\" will be used.\n\n";
			}
			
			if( not defined $pin ) {
				$pin = "NONE";
			} elsif( $provider eq "wilmaa.com" ) {
				$pin = "NONE";
			} elsif( $pin eq "" ) {
				$pin = "NONE";
			} elsif( $pin =~ /[0-9][0-9][0-9][0-9]/ ) {
				INFO "Youth protection pin will be used to request channel playlists.\n\n";
			} else {
				INFO "Youth protection pin must consist of 4 numbers - pin disabled.\n\n";
				$pin = "NONE";
			}
			
			if( not defined $ssl_mode ) {
				$ssl_mode = "1";
			} elsif( $ssl_mode eq "0" ) {
				INFO "WARNING: SSL verification disabled!\n\n";
			}
			
			# CHECK PROVIDER
			if( $provider eq "www.zattoo.com" ) {
				$provider = "zattoo.com";
			} elsif( $provider =~ /zattoo.com|wilmaa.com|www.1und1.tv|mobiltv.quickline.com|tvplus.m-net.de|player.waly.tv|www.meinewelt.cc|www.bbv-tv.net|www.vtxtv.ch|www.myvisiontv.ch|iptv.glattvision.ch|www.saktv.ch|nettv.netcologne.de|tvonline.ewe.de|www.quantum-tv.com|tv.salt.ch|tvonline.swb-gruppe.de|tv.eir.ie/ ) {
				print "";
			} else {
				ERROR "ERROR: Provider is not supported. Please recheck the domain.\n\n";
				open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
				print $error_file "ERROR: Provider is not supported. Please recheck the domain.";
				close $error_file;
				exit;
			}
			
			if( $provider eq "wilmaa.com" ) {
				
				#
				# WILMAA
				#
				
				# LOOKUP IP ADDRESS VIA CHANNEL M3U UPDATE TIME
				
				# URLs
				my $channel_url = "http://geo.wilmaa.com/channels/basic/web_hls_de.json";
				
				# CHANNEL M3U REQUEST
				my $channel_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $channel_request  = HTTP::Request::Common::GET($channel_url);
				my $channel_response = $channel_agent->request($channel_request);
				
				if( $channel_response->is_error ) {
					ERROR "ERROR: IP lookup: Invalid response\n\n";
					ERROR "RESPONSE:\n\n" . $channel_response->content . "\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: IP lookup: Invalid response";
					close $error_file;
					exit;
				}
				
				# READ JSON
				my $ch_file;
				
				eval{
					$ch_file = decode_json($channel_response->content);
				};
				
				if( not defined $ch_file ) {
					ERROR "ERROR: Failed to parse JSON file(s) (IP LOOKUP)\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: Failed to parse JSON file(s) (IP LOOKUP)";
					close $error_file;
					exit;
				}
				
				my $m3u_date = $ch_file->{"channelList"}{"published_at"};
				my $country_code;
				my $tv_mode;
				
				if( defined $m3u_date ) {
					if( $m3u_date eq "2018-04-05 14:52:02" ) {
						$country_code = "DE";
					} else {
						$country_code = "CH";
					}
				} else {
					$country_code = "DE";
				}
				
				if( $country_code ne "CH" and defined $login_mail and defined $login_passwd ) {
					INFO "--- YOUR ACCOUNT TYPE: WILMAA ---\n\n";
					INFO "--- COUNTRY: OTHER ---\n\n";
					INFO "No Swiss IP address detected, Live TV feature is disabled.\n\n";
					$tv_mode = "pvr";
				} elsif( $country_code ne "CH" ) {
					INFO "--- YOUR ACCOUNT TYPE: WILMAA (ANONYMOUS) ---\n\n";
					INFO "--- COUNTRY: OTHER ---\n\n";
					INFO "ERROR: No valid service country detected, Wilmaa services can't be used.\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: No valid service country detected, Wilmaa services can't be used.";
					close $error_file;
					exit;
				} elsif( $country_code eq "CH" and defined $login_mail and defined $login_passwd ) {
					INFO "--- YOUR ACCOUNT TYPE: WILMAA ---\n\n";
					INFO "--- COUNTRY: SWITZERLAND ---\n\n";
					$tv_mode = "live";
				} else {
					INFO "--- YOUR ACCOUNT TYPE: WILMAA (ANONYMOUS) ---\n\n";
					INFO "--- COUNTRY: SWITZERLAND ---\n\n";
					$tv_mode = "live";
				}
				
				if( defined $login_mail and defined $login_passwd ) {
					
					# GET APPTOKEN + SESSION ID
					my $main_url      = "https://www.wilmaa.com/de/my/headless/login?callback=undefined";
				
					my $main_agent    = LWP::UserAgent->new(
						ssl_opts => {
							SSL_verify_mode => $ssl_mode,
							verify_hostname => $ssl_mode,
							SSL_ca_file => Mozilla::CA::SSL_ca_file()  
						},
						agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
					);

					my $main_request  = HTTP::Request::Common::GET($main_url);
					my $main_response = $main_agent->request($main_request);
					my $session_token    = $main_response->header('Set-cookie');
					
					if( defined $session_token ) {
						$session_token       =~ s/(.*)(wilmaa=)(.*)(; expires.*)/$3/g;
					} else {
						ERROR "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve Session ID)\n\n";
						open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
						print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve Session ID)";
						close $error_file;
						exit;
					}

					my $parser        = HTML::Parser->new;
					my $main_content  = $main_response->content;

					if( not defined $main_content) {
						ERROR "UNABLE TO LOGIN TO WEBSERVICE! (empty webpage content)\n\n";
						open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
						print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (empty webpage content)";
						close $error_file;
						exit;
					}

					my $wilmaatree   = HTML::TreeBuilder->new;
					$wilmaatree->parse($main_content);

					if( not defined $wilmaatree) {
						ERROR "UNABLE TO LOGIN TO WEBSERVICE! (unable to parse webpage)\n\n";
						open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
						print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (unable to parse webpage)";
						close $error_file;
						exit;
					}

					my @scriptvalues = $wilmaatree->look_down('name' => 'csrf_token');
					my $apptoken     = $scriptvalues[0]->as_HTML;
					
					if( defined $apptoken ) {
						$apptoken        =~ s/(.*value=")(.*)(".*)/$2/g;
					} else {
						ERROR "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve appToken)\n\n";
						open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
						print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve appToken)";
						close $error_file;
						exit;
					}
					
					# GET LOGIN COOKIE
					my $login_url    = "https://www.wilmaa.com/de/my/headless/login?callback=undefined";
					
					my $login_agent   = LWP::UserAgent->new(
						ssl_opts => {
							SSL_verify_mode => $ssl_mode,
							verify_hostname => $ssl_mode,
							SSL_ca_file => Mozilla::CA::SSL_ca_file()  
						},
						agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
					);
					
					my $cookie_jar    = HTTP::Cookies->new;
					$cookie_jar->set_cookie(0,'wilmaa',$session_token,'/','.wilmaa.com',443);
					$login_agent->cookie_jar($cookie_jar);

					my $login_request  = HTTP::Request::Common::POST($login_url, ['username' => $login_mail, 'password' => $login_passwd, 'csrf_token' => $apptoken, 'login_form' => 'true' ]);
					my $login_response = $login_agent->request($login_request);
					my $login_user     = $login_response->header('set-cookie');
					
					if( not defined $login_user ) {
						ERROR "LOGIN FAILED! (please re-check login data)\n\n";
						open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
						print $error_file "LOGIN FAILED! (please re-check login data)";
						close $error_file;
						exit;
					} else {
						INFO "LOGIN OK!\n\n";
					}
					
					$login_user       =~ s/(.*)(wilmaa_user_id=)(.*)(; expires.*)(wilmaa_onboarding_user_id.*)/$3/g;
					
					# CREATE FILE
					open my $session_file, ">", "session.json" or die "UNABLE TO CREATE SESSION FILE!\n\n";
					print $session_file "{\"provider\":\"$provider\",\"tv_mode\":\"$tv_mode\",\"wilmaa_user_id\":\"$login_user\",\"session_token\":\"$session_token\",\"interface\":\"$interface\",\"address\":\"$customip\",\"server\":\"$zserver\",\"ffmpeg_lib\":\"$ffmpeglib\",\"port\":\"$port\",\"ssl_mode\":\"$ssl_mode\"}";
					close $session_file;
					
					sleep 86400;
					truncate 'log.txt', 0;
				
				}
				
				# CREATE FILE
				open my $session_file, ">", "session.json" or die "UNABLE TO CREATE SESSION FILE!\n\n";
				print $session_file "{\"provider\":\"$provider\",\"tv_mode\":\"$tv_mode\",\"interface\":\"$interface\",\"address\":\"$customip\",\"server\":\"$zserver\",\"ffmpeg_lib\":\"$ffmpeglib\",\"port\":\"$port\",\"ssl_mode\":\"$ssl_mode\"}";
				close $session_file;
				
				sleep 86400;
				truncate 'log.txt', 0;
				
			} else {
				
				#
				# ZATTOO
				#

				# GET APPTOKEN
				my $main_url      = "https://$provider/";
				
				my $main_agent    = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);

				my $main_request  = HTTP::Request::Common::GET($main_url);
				my $main_response = $main_agent->request($main_request);

				if( $main_response->is_error ) {
					ERROR "UNABLE TO LOGIN TO WEBSERVICE! (no internet connection / service unavailable)\n\n";
					ERROR "RESPONSE:\n\n" . $main_response->content . "\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (no internet connection / service unavailable)";
					close $error_file;
					exit;
				}

				my $parser        = HTML::Parser->new;
				my $main_content  = $main_response->content;

				if( not defined $main_content) {
					ERROR "UNABLE TO LOGIN TO WEBSERVICE! (empty webpage content)\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (empty webpage content)";
					close $error_file;
					exit;
				}

				my $zattootree   = HTML::TreeBuilder->new;
				$zattootree->parse($main_content);

				if( not defined $zattootree) {
					ERROR "UNABLE TO LOGIN TO WEBSERVICE! (unable to parse webpage)\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (unable to parse webpage)";
					close $error_file;
					exit;
				}

				my @scriptvalues = $zattootree->look_down('type' => 'text/javascript');
				my $apptoken     = $scriptvalues[0]->as_HTML;
				
				if( defined $apptoken ) {
					$apptoken        =~ s/(.*window.appToken = ')(.*)(';.*)/$2/g;
				} else {
					ERROR "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve appToken)\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve appToken)";
					close $error_file;
					exit;
				}

				# GET SESSION ID
				my $session_url    = "https://$provider/zapi/session/hello";
				
				my $session_agent  = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);

				my $session_request  = HTTP::Request::Common::POST($session_url, ['client_app_token' => uri_escape($apptoken), 'uuid' => uri_escape('d7512e98-38a0-4f01-b820-5a5cf98141fe'), 'lang' => uri_escape('en'), 'format' => uri_escape('json')]);
				my $session_response = $session_agent->request($session_request);
				my $session_token    = $session_response->header('Set-cookie');
				
				if( defined $session_token ) {
					$session_token       =~ s/(.*)(beaker.session.id=)(.*)(; Path.*)/$3/g;
				} else {
					ERROR "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve Session ID)\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "UNABLE TO LOGIN TO WEBSERVICE! (unable to retrieve Session ID)";
					close $error_file;
					exit;
				}

				if( $session_response->is_error ) {
					ERROR "LOGIN FAILED! (invalid response)\n\n";
					ERROR "RESPONSE:\n\n" . $session_response->content . "\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "LOGIN FAILED! (invalid response)";
					close $error_file;
					exit;
				}

				# GET LOGIN COOKIE
				my $login_url    = "https://$provider/zapi/v2/account/login";
				
				my $login_agent   = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $cookie_jar    = HTTP::Cookies->new;
				$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/',$provider,443);
				$login_agent->cookie_jar($cookie_jar);

				my $login_request  = HTTP::Request::Common::POST($login_url, ['login' => $login_mail, 'password' => $login_passwd ]);
				my $login_response = $login_agent->request($login_request);

				if( $login_response->is_error ) {
					ERROR "LOGIN FAILED! (please re-check login data)\n\n";
					ERROR "RESPONSE:\n\n" . $login_response->content . "\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "LOGIN FAILED! (please re-check login data)";
					close $error_file;
					exit;
				} else {
					INFO "LOGIN OK!\n\n";
				}

				my $login_token    = $login_response->header('Set-cookie');
				$login_token       =~ s/(.*)(beaker.session.id=)(.*)(; Path.*)/$3/g;

				# ANALYSE ACCOUNT
				my $analyse_login;
				
				eval{
					$analyse_login = decode_json($login_response->content);
				};

				if( not defined $analyse_login ) {
					ERROR "ERROR: Unable to parse user data\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: Unable to parse user data";
					close $error_file;
					exit;
				}

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
				
				if( not defined $country ) {
					$country = "XX";
				}
				
				if( $country eq "CH" ) {
					INFO "--- COUNTRY: SWITZERLAND ---\n\n";
				} elsif( $country eq "DE" ) {
					INFO "--- COUNTRY: GERMANY ---\n\n";
				} elsif( $provider eq "zattoo.com" ) {
					ERROR "--- COUNTRY: OTHER ---\n\n";
					ERROR "ERROR: No valid service country detected, Zattoo services can't be used.\n\n";
					open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
					print $error_file "ERROR: No valid service country detected, Zattoo services can't be used.";
					close $error_file;
					exit;
				} else {
					print "--- COUNTRY: OTHER ---\n\n";
				}

				if( defined $product_code ) {
					if( $product_code eq "PREMIUM" ) {
						INFO "--- YOUR ACCOUNT TYPE: ZATTOO PREMIUM ---\n\n";
					} elsif( $product_code eq "ULTIMATE" ) {
						INFO "--- YOUR ACCOUNT TYPE: ZATTOO ULTIMATE ---\n\n";
					}
				} elsif( $provider eq "zattoo.com" ) {
					INFO "--- YOUR ACCOUNT TYPE: ZATTOO FREE ---\n\n";
					$product_code = "FREE";
				} else {
					INFO "--- YOUR ACCOUNT TYPE: RESELLER ---\n\n";
				}

				my $tv_mode;

				if( $country eq "CH" and $provider eq "zattoo.com" ) {
					
					if( $alias ne "CH" and $product_code ne "FREE" ) {
						INFO "No Swiss IP address detected, using PVR mode for Live TV.\n\n";
						$tv_mode = "pvr";
					} elsif ( $alias ne "CH" and $product_code eq "FREE" ) {
						ERROR "ERROR: No Swiss IP address detected, Zattoo services can't be used.\n\n";
						open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
						print $error_file "ERROR: No Swiss IP address detected, Zattoo services can't be used.";
						close $error_file;
						exit;
					} else {
						$tv_mode = "live";
					}
					
				} elsif( $country eq "DE" and $provider eq "zattoo.com" ) {
					
					if( $alias ne "DE" and $product_code eq "FREE" ) {
						ERROR "ERROR: No German IP address detected, Zattoo services can't be used.\n\n";
						open my $error_file, ">", "error.txt" or die "UNABLE TO CREATE ERROR FILE!\n\n";
						print $error_file "ERROR: No German IP address detected, Zattoo services can't be used.";
						close $error_file;
						exit;
					} elsif( $alias ne "DE" and $product_code =~ /PREMIUM|ULTIMATE/ ) {
						if( $alias =~ /BE|FR|IT|LU|NL|DK|IE|UK|GR|PT|ES|FI|AT|SE|EE|LT|LV|MT|PL|SK|SI|CZ|HU|CY|BG|RO|HR|GP|GY|MQ|RE|YT|AN/ ) {
							INFO "No German IP address detected, Zattoo services can be used within the EU.\n\n";
							$tv_mode = "live";
						}
					} else {
						$tv_mode = "live";
					}
				
				} else {
					$tv_mode = "live";
				}
				
				# CREATE FILE
				open my $session_file, ">", "session.json" or die "UNABLE TO CREATE SESSION FILE!\n\n";
				print $session_file "{\"provider\":\"$provider\",\"session_token\":\"$session_token\",\"powerid\":\"$powerid\",\"tv_mode\":\"$tv_mode\",\"country\":\"$country\",\"interface\":\"$interface\",\"address\":\"$customip\",\"server\":\"$zserver\",\"ffmpeg_lib\":\"$ffmpeglib\",\"port\":\"$port\",\"pin\":\"$pin\",\"ssl_mode\":\"$ssl_mode\"}";
				close $session_file;
				
				sleep 86400;
				truncate 'log.txt', 0;
			
			}
		
		}
	
	}

}

# TRIGGER LOGIN PROCESS
unlink "session.json";
login_process();

until( -e "session.json" ) {
	if( -e "error.txt" ) {
		open( my $fh, "<", "error.txt" );
		my $file_content = do { local $/; <$fh> };
		print $file_content;
		close $fh;
		unlink "error.txt";
		print "API PROCESS STOPPED!\n\n";
		exit;
	}
	sleep 1;
}


#
# HTTP DAEMON PROCESS
#

# DEFINE PARAMS
my %O = (
    'clients' => 10,
    'max-req' => 100,
);

# READ SESSION FILE TO GET INTERFACE IP ADDRESS
my $json_file;
{
	local $/; #Enable 'slurp' mode
	open my $fh, "<", "session.json" or die "UNABLE TO OPEN SESSION FILE! (please check file existence/permissions)\n\n";
	$json_file = <$fh>;
	close $fh;
}
	
# READ JSON
my $sessiondata;

eval{
	$sessiondata = decode_json($json_file);
};
	
if( not defined $sessiondata ) {
	print "ERROR: Failed to parse JSON session file.\n\n";
	exit;
}
		
# SET INTERFACE PARAMS
my $address   = $sessiondata->{"address"};
my $interface = $sessiondata->{"interface"};
my $port      = $sessiondata->{"port"};

my $hostipchecker;
my $hostip;

if( defined $address ) {
	if( $address eq "" ) {
		undef $address;
	}
}

if( defined $interface ) {
	if( $interface eq "" ) {
		undef $interface;
	}
}

if( defined $address ) {

	$hostip = $address;

} elsif( defined $interface ) {
	
	# USE CUSTOM INTERFACE
	$hostipchecker = IO::Interface::Simple->new( "$interface" );
	
	if( defined $hostipchecker ) {
		
		if ( $hostipchecker->is_broadcast ) {
			$hostip = $hostipchecker->address;
		} else {
			print "ERROR: Custom interface can't be used (no broadcast type).\n\n";
			exit;
		}
		
	} else {
		
		print "ERROR: Custom interface can't be used (unknown).\n\n";
		exit;
	
	}
	
} else {
	
	# USE FIRST INTERFACE
	my @interfaces = IO::Interface::Simple->interfaces;
	
	for my $hostipchecker ( @interfaces ) {
		if ( $hostipchecker->is_broadcast ) {
			if( not defined $hostip ) {
				$hostip = $hostipchecker->address;
			}
		}
	}
	
	if( not defined $hostip ) {
		print "ERROR: Broadcast interface can't be found!\n\n";
		exit;
	}
}


# START DAEMON
my $d = HTTP::Daemon->new(
    LocalAddr => $hostip,
    LocalPort => $port,
    Reuse => 1,
	ReuseAddr => 1,
	ReusePort => $port,
) or die "API CANNOT BE STARTED!\nPlease recheck your IP/domain/port configuration.\n\n";

print "API STARTED!\n\n";
print "Host IP address: $hostip:$port\n\n";

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
            } else { # CHILD
				$_ = 'DEFAULT' for @SIG{qw/ INT TERM CHLD /};
				http_child($d);
				exit;
            }
        }
    } else {
        http_child($d);
    }
    sleep 60;
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
		my $rec_ch  = $params->{'recording'};
		
		# SET QUALITY
		my $quality = $params->{'bw'};
		
		# SET DOLBY
		my $dolby = $params->{'dolby'};
		
		# SET 2ND AUDIO STREAM
		my $audio2 = $params->{'audio2'};
		
		# SET PLATFORM
		my $platform = $params->{'platform'};
		
		# SET FILE
		my $filename  = $params->{'file'};
		my $favorites = $params->{'favorites'};
		my $ffmpeg    = $params->{'ffmpeg'};
		
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
		
		# SET REMOVE FLAG
		my $remove   = $params->{'remove'};
		
		# SET MULTIAUDIO PROFILE
		my $multi    = $params->{'profile'};
		
		# READ SESSION FILE
		my $json;
		{
			local $/; #Enable 'slurp' mode
			open my $fh, "<", "session.json" or die "UNABLE TO OPEN SESSION FILE! (please check file existence/permissions)\n\n";
			$json = <$fh>;
			close $fh;
		}
		
		# READ JSON
		my $session_data;
		
		eval{
			$session_data = decode_json($json);
		};
		
		if( not defined $session_data ) {
			print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Failed to parse JSON file (SESSION)\n\n";
					
			my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
			$response->header('Content-Type' => 'text'),
			$response->content("API ERROR: Failed to parse JSON file (SESSION)");
			$c->send_response($response);
			$c->close;
			exit;
		}
		
		# SET SESSION PARAMS
		my $provider      = $session_data->{"provider"};
		my $session_token = $session_data->{"session_token"};
		my $country       = $session_data->{"country"};
		my $tv_mode       = $session_data->{"tv_mode"};
		my $powerid       = $session_data->{"powerid"};
		my $server        = $session_data->{"server"};
		my $ffmpeglib     = $session_data->{"ffmpeg_lib"};
		my $pin           = $session_data->{"pin"};
		my $ssl_mode      = $session_data->{"ssl_mode"};
		my $w_user_id     = $session_data->{"wilmaa_user_id"};
		
		#
		# RETRIEVE FILES
		#
		
		if( defined $filename and defined $quality and defined $platform ) {
			
			#
			# ZATTOO CHANNEL LIST
			#
			
			if( $filename eq "channels.m3u" and $quality =~ /8000|5000|4999|3000|2999|1500/ and $platform =~ /hls|hls5/ and $provider ne "wilmaa.com" ) {
				
				# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
				if( open my $file, "<", "channels_m3u:$quality:$platform:cached" ) {
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$c->send_file_response("channels_m3u:$quality:$platform:cached");
					$c->close;
					close $file;
					unlink "channels_m3u:$quality:$platform:cached";
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Channel list resent to client - params: bandwidth=$quality, platform=$platform\n";
					exit;
				}	
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Loading channel data\n";
				
				# URLs
				my $channel_url   = "https://$provider/zapi/v2/cached/channels/$powerid?details=False";
				my $fav_url       = "https://$provider/zapi/channels/favorites";
				my $rytec_url     = "https://raw.githubusercontent.com/sunsettrack4/config_files/master/ztt_channels.json";
				
				# COOKIE
				my $cookie_jar    = HTTP::Cookies->new;
				$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/',$provider,443);
				
				# CHANNEL M3U REQUEST
				my $channel_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				$channel_agent->cookie_jar($cookie_jar);
				my $channel_request  = HTTP::Request::Common::GET($channel_url);
				my $channel_response = $channel_agent->request($channel_request);
				
				if( $channel_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Channel URL: Invalid response\n\n";
					print "RESPONSE:\n\n" . $channel_response->content . "\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Invalid response on channel request");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# FAVORITES REQUEST
				my $fav_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				$fav_agent->cookie_jar($cookie_jar);
				my $fav_request  = HTTP::Request::Common::GET($fav_url);
				my $fav_response = $fav_agent->request($fav_request);
				
				if( $fav_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Favorites URL: Invalid response\n\n";
					print "RESPONSE:\n\n" . $fav_response->content . "\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Invalid response on favorites request");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# RYTEC REQUEST
				my $rytec_agent    = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $rytec_request  = HTTP::Request::Common::GET($rytec_url);
				my $rytec_response = $rytec_agent->request($rytec_request);
				
				if( $rytec_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Rytec URL: Invalid response\n\n";
					print "RESPONSE:\n\n" . $rytec_response->content . "\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Invalid response on Rytec request");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# READ JSON
				my $ch_file;
				my $fav_file;
				my $rytec_file;
				
				eval{
					$ch_file    = decode_json($channel_response->content);
					$fav_file   = decode_json($fav_response->content);
					$rytec_file = decode_json($rytec_response->content);
				};
				
				if( not defined $ch_file or not defined $fav_file or not defined $rytec_file ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Failed to parse JSON file(s) (CH LIST)\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Failed to parse JSON file(s) (CH LIST)");
					$c->send_response($response);
					$c->close;
					exit;
				}

				# SET UP VALUES
				my @ch_groups = @{ $ch_file->{'channel_groups'} };
				my @fav_items = @{ $fav_file->{'favorites'} };
				my $rytec_id  = $rytec_file->{'channels'}->{$country};
				
				# CREATE CHANNELS M3U
				my $ch_m3u   = "#EXTM3U\n";
				
				foreach my $ch_groups ( @ch_groups ) {
					my @channels = @{ $ch_groups->{'channels'} };
					my $group    = $ch_groups->{'name'};
					
					if( defined $favorites ) {
							
						foreach my $fav_items ( @fav_items ) {
					
							foreach my $channels ( @channels ) {
								my $name    = $channels->{'title'};
								my $service = $channels->{'title'} =~ s/\//\\\\\//g;
								my $chid    = $channels->{'cid'};
								my $alias   = $channels->{'display_alias'};
								
								if( $channels->{'cid'} eq $fav_items ) {
									if( defined $channels->{'qualities'} ) {
										
										# IF FIRST CHANNEL TYPE IS "AVAILABLE", PRINT M3U LINE
										if( $channels->{'qualities'}[0]{'availability'} eq "available" ) {
											my $logo = $channels->{'qualities'}[0]{'logo_black_84'};
											$logo =~ s/84x48.png/210x120.png/g;
											
											if( $country =~ /DE|CH/ and defined $rytec_id->{$name} ) {
												$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $rytec_id->{$name} . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
											} else {
												$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $name . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
											}
											
											if( defined $multi ) {
												if( defined $ffmpeg and $multi eq "1" ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( defined $ffmpeg and $multi eq "2" ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( defined $ffmpeg and $multi eq "3" ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( defined $ffmpeg ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( $multi eq "1" ) {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\n";
												} elsif( $multi eq "2" ) {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\n";
												} elsif( $multi eq "3" ) {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
												} else {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
												}
											} elsif( defined $ffmpeg and defined $dolby and defined $audio2 ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( defined $ffmpeg and defined $dolby ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( defined $ffmpeg and defined $audio2 ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( defined $ffmpeg ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( defined $dolby and defined $audio2 ) {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\n";
											} elsif( defined $dolby ) {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\n";
											} elsif( defined $audio2 ) {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\n";
											} else {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
											}
										
										# IF 1st CHANNEL TYPE IS "SUBSCRIBABLE" + 2nd CHANNEL TYPE IS "AVAILABLE", PRINT M3U LINE
										} elsif( defined $channels->{'qualities'}[1]{'availability'} ) {
											if( $channels->{'qualities'}[1]{'availability'} eq "available" ) {
												my $logo = $channels->{'qualities'}[1]{'logo_black_84'};
												$logo =~ s/84x48.png/210x120.png/g;
												
												if( $country =~ /DE|CH/ and defined $rytec_id->{$name} ) {
													$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $rytec_id->{$name} . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
												} else {
													$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $name . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
												}
												
												
												if( defined $multi ) {
													if( defined $ffmpeg and $multi eq "1" ) {
														$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
													} elsif( defined $ffmpeg and $multi eq "2" ) {
														$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
													} elsif( defined $ffmpeg and $multi eq "3" ) {
														$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
													} elsif( defined $ffmpeg ) {
														$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
													} elsif( $multi eq "1" ) {
														$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\n";
													} elsif( $multi eq "2" ) {
														$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\n";
													} elsif( $multi eq "3" ) {
														$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
													} else {
														$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
													}
												} elsif( defined $ffmpeg and defined $dolby and defined $audio2 ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( defined $ffmpeg and defined $dolby ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( defined $ffmpeg and defined $audio2 ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( defined $ffmpeg ) {
													$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
												} elsif( defined $dolby and defined $audio2 ) {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\n";
												} elsif( defined $dolby ) {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\n";
												} elsif( defined $audio2 ) {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\n";
												} else {
													$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
												}
											}
										}
									}
								}
							}
						}
							
					} else {
						
						foreach my $channels ( @channels ) {
							my $name    = $channels->{'title'};
							my $service = $channels->{'title'} =~ s/\//\\\\\//g;
							my $chid    = $channels->{'cid'};
							my $alias   = $channels->{'display_alias'};
							
							if( defined $channels->{'qualities'} ) {
								
								# IF FIRST CHANNEL TYPE IS "AVAILABLE", PRINT M3U LINE
								if( $channels->{'qualities'}[0]{'availability'} eq "available" ) {
									my $logo = $channels->{'qualities'}[0]{'logo_black_84'};
									$logo =~ s/84x48.png/210x120.png/g;
									
									if( $country =~ /DE|CH/ and defined $rytec_id->{$name} ) {
										$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $rytec_id->{$name} . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
									} else {
										$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $name . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
									}
									
									if( defined $multi ) {
										if( defined $ffmpeg and $multi eq "1" ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( defined $ffmpeg and $multi eq "2" ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( defined $ffmpeg and $multi eq "3" ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( defined $ffmpeg ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( $multi eq "1" ) {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\n";
										} elsif( $multi eq "2" ) {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\n";
										} elsif( $multi eq "3" ) {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
										} else {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
										}
									} elsif( defined $ffmpeg and defined $dolby and defined $audio2 ) {
										$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
									} elsif( defined $ffmpeg and defined $dolby ) {
										$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
									} elsif( defined $ffmpeg and defined $audio2 ) {
										$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
									} elsif( defined $ffmpeg ) {
										$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
									} elsif( defined $dolby and defined $audio2 ) {
										$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\n";
									} elsif( defined $dolby ) {
										$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\n";
									} elsif( defined $audio2 ) {
										$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\n";
									} else {
										$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
									}
								
								# IF 1st CHANNEL TYPE IS "SUBSCRIBABLE" + 2nd CHANNEL TYPE IS "AVAILABLE", PRINT M3U LINE
								} elsif( defined $channels->{'qualities'}[1]{'availability'} ) {
									if( $channels->{'qualities'}[1]{'availability'} eq "available" ) {
										my $logo = $channels->{'qualities'}[1]{'logo_black_84'};
										$logo =~ s/84x48.png/210x120.png/g;
										
										if( $country =~ /DE|CH/ and defined $rytec_id->{$name} ) {
											$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $rytec_id->{$name} . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
										} else {
											$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $name . "\" group-title=\"" . $group . "\" tvg-logo=\"https://images.zattic.com" . $logo . "\", " . $name . "\n";
										}
										
										if( defined $multi ) {
											if( defined $ffmpeg and $multi eq "1" ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( defined $ffmpeg and $multi eq "2" ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( defined $ffmpeg and $multi eq "3" ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( defined $ffmpeg ) {
												$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
											} elsif( $multi eq "1" ) {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\n";
											} elsif( $multi eq "2" ) {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\n";
											} elsif( $multi eq "3" ) {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
											} else {
												$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
											}
										} elsif( defined $ffmpeg and defined $dolby and defined $audio2 ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( defined $ffmpeg and defined $dolby ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( defined $ffmpeg and defined $audio2 ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( defined $ffmpeg ) {
											$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
										} elsif( defined $dolby and defined $audio2 ) {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\n";
										} elsif( defined $dolby ) {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\n";
										} elsif( defined $audio2 ) {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\n";
										} else {
											$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
										}
									}
								}
							}
						}
					}
				}
				
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text', 'Charset' => 'utf8'),
				$response->content(Encode::encode_utf8($ch_m3u));
				$c->send_response($response);
				$c->close;
				
				# CACHE PLAYLIST
				open my $cachedfile, ">", "channels_m3u:$quality:$platform:cached";
				print $cachedfile "$ch_m3u";
				close $cachedfile;
				
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Channel list sent to client - params: bandwidth=$quality, platform=$platform\n";
				
				# REMOVE CACHED PLAYLIST
				sleep 1;
				unlink "channels_m3u:$quality:$platform:cached";
				exit;
			
			
			#
			# WILMAA CHANNEL LIST
			#
			
			} elsif( $filename eq "channels.m3u" and $quality =~ /8000|5000|4999|3000|2999|1500/ and $platform =~ /hls5/ and $provider eq "wilmaa.com" ) {
				
				# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
				if( open my $file, "<", "channels_m3u:$quality:$platform:cached" ) {
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$c->send_file_response("channels_m3u:$quality:$platform:cached");
					$c->close;
					close $file;
					unlink "recordings_m3u:$quality:$platform:cached";
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Channel list resent to client - params: bandwidth=$quality, platform=$platform\n";
					exit;
				}	
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Loading channels data\n";
				
				# URLs
				my $channel_url = "http://geo.wilmaa.com/channels/basic/web_hls_de.json";
				my $mapping_url = "https://resources.wilmaa.com/channelsOverview/channelMappings.json";
				
				# CHANNEL M3U REQUEST
				my $channel_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $channel_request  = HTTP::Request::Common::GET($channel_url);
				my $channel_response = $channel_agent->request($channel_request);
				
				if( $channel_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Channel URL: Invalid response\n\n";
					print "RESPONSE:\n\n" . $channel_response->content . "\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Invalid response on channel request");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# CHANNEL MAPPING REQUEST
				my $mapping_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $mapping_request  = HTTP::Request::Common::GET($mapping_url);
				my $mapping_response = $mapping_agent->request($mapping_request);
				
				if( $mapping_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Mapping URL: Invalid response\n\n";
					print "RESPONSE:\n\n" . $mapping_response->content . "\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Invalid response on channel request");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# READ JSON
				my $ch_file;
				my $mapfile;
				
				eval{
					$ch_file    = decode_json($channel_response->content);
					$mapfile    = decode_json($mapping_response->content);
				};
				
				if( not defined $ch_file or not defined $mapfile ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Failed to parse JSON file(s) (CH LIST)\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Failed to parse JSON file(s) (CH LIST)");
					$c->send_response($response);
					$c->close;
					exit;
				}

				# SET UP VALUES
				my @channels     = @{ $ch_file->{"channelList"}{"channels"} };
				my @categories   = @{ $ch_file->{"channelList"}{"defaults"}{"categories"} };
				my @dolbysupport = @{ $mapfile->{"extraSettings"}{"dolbyDigital"} };
				
				# CREATE CHANNELS M3U
				my $ch_m3u   = "#EXTM3U\n";
				
				foreach my $channel ( @channels ) {
					my $chid   = $channel->{"id"};
					my $name   = $channel->{"label"}{"name"};
					my $cat    = $channel->{"label"}{"category"};
					
					foreach my $category ( @categories ) {
						my $cat_id   = $category->{"id"};
						my $cat_name = $category->{"languages"}[0]{"de"};
						
						if( $cat eq $cat_id ) {
							$ch_m3u = $ch_m3u . "#EXTINF:0001 tvg-id=\"" . $name . "\" group-title=\"" . $cat_name . "\" tvg-logo=\"https://resources.wilmaa.com/logos/single/dark/center/360x120px/" . $chid . ".png\", " . $name . "\n";
							
							my $dd_location;
							
							foreach my $dolbysupport ( @dolbysupport ) {
								if( $dolbysupport eq $chid ) {
									$dd_location = "true";
								}
							}
							
							if( defined $multi ) {
								if( defined $ffmpeg and $multi eq "1" and defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
								} elsif( defined $ffmpeg and $multi eq "1" and not defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
								} elsif( defined $ffmpeg and $multi eq "2" and defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
								} elsif( defined $ffmpeg and $multi eq "2" and not defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
								} elsif( defined $ffmpeg and $multi eq "3" ) {
									$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
								} elsif( defined $ffmpeg ) {
									$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
								} elsif( $multi eq "1" and defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\n";
								} elsif( $multi eq "1" and not defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
								} elsif( $multi eq "2" and defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\n";
								} elsif( $multi eq "1" and not defined $dd_location ) {
									$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
								} elsif( $multi eq "3" ) {
									$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
								} else {
									$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
								}
							} elsif( defined $ffmpeg and defined $dolby and defined $audio2 and defined $dd_location ) {
								$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
							} elsif( defined $ffmpeg and defined $dolby and defined $dd_location ) {
								$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
							} elsif( defined $ffmpeg and defined $audio2 ) {
								$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
							} elsif( defined $ffmpeg ) {
								$ch_m3u = $ch_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $name . "\" pipe:1\n";
							} elsif( defined $dolby and defined $audio2 and defined $dd_location ) {
								$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\n";
							} elsif( defined $dolby and defined $dd_location ) {
								$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\n";
							} elsif( defined $audio2 ) {
								$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\n";
							} else {
								$ch_m3u = $ch_m3u .  "http://$hostip:$port/index.m3u8?channel=" . $chid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
							}
							
							undef $dd_location;
						}
					}
				}
					
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text', 'Charset' => 'utf8'),
				$response->content(Encode::encode_utf8($ch_m3u));
				$c->send_response($response);
				$c->close;
				
				# CACHE PLAYLIST
				open my $cachedfile, ">", "channels_m3u:$quality:$platform:cached";
				print $cachedfile "$ch_m3u";
				close $cachedfile;
				
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Channel list sent to client - params: bandwidth=$quality, platform=$platform\n";
				
				# REMOVE CACHED PLAYLIST
				sleep 1;
				unlink "channels_m3u:$quality:$platform:cached";
				exit;

			
			#
			# ZATTOO RECORDING LIST
			#
			
			} elsif( $filename eq "recordings.m3u" and $quality =~ /8000|5000|4999|3000|2999|1500/ and $platform =~ /hls|hls5/ and $provider ne "wilmaa.com" ) {
				
				# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
				if( open my $file, "<", "recordings_m3u:$quality:$platform:cached" ) {
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$c->send_file_response("recordings_m3u:$quality:$platform:cached");
					$c->close;
					close $file;
					unlink "recordings_m3u:$quality:$platform:cached";
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Recording list resent to client - params: bandwidth=$quality, platform=$platform\n";
					exit;
				}	
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Loading recordings data\n";
				
				# URLs
				my $channel_url   = "https://$provider/zapi/v2/cached/channels/$powerid?details=False";
				my $playlist_url  = "https://$provider/zapi/playlist";
				
				# COOKIE
				my $cookie_jar    = HTTP::Cookies->new;
				$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/',$provider,443);
				
				# RECORDING M3U REQUEST
				my $channel_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				$channel_agent->cookie_jar($cookie_jar);
				my $channel_request  = HTTP::Request::Common::GET($channel_url);
				my $channel_response = $channel_agent->request($channel_request);
				
				if( $channel_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Recording URL: Invalid response\n\n";
					print "RESPONSE:\n\n" . $channel_response->content . "\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Invalid response on recording request");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# RECORDING M3U REQUEST
				my $playlist_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				$playlist_agent->cookie_jar($cookie_jar);
				my $playlist_request  = HTTP::Request::Common::GET($playlist_url);
				my $playlist_response = $playlist_agent->request($playlist_request);
				
				if( $playlist_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: No permission to use PVR mode\n";
					
					my $response = HTTP::Response->new( 403, 'FORBIDDEN');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: No permission to use PVR mode");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# READ JSON
				my $ch_file;
				my $playlist_file;
				
				eval{
					$ch_file       = decode_json($channel_response->content);
					$playlist_file = decode_json($playlist_response->content);
				};
				
				if( not defined $ch_file or not defined $playlist_file ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Failed to parse JSON file(s) (REC LIST)\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Failed to parse JSON file (REC LIST)");
					$c->send_response($response);
					$c->close;
					exit;
				}

				# SET UP VALUES
				my @ch_groups = @{ $ch_file->{'channel_groups'} };
				my @rec_data  = @{ $playlist_file->{'recordings'} };
				
				if( not defined $playlist_file->{'recordings'}[0]{title} ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: No recordings found\n";
					
					my $response = HTTP::Response->new( 404, 'NOT FOUND');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: No recordings found");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# CREATE RECORDING M3U
				my $rec_m3u   = "#EXTM3U\n";
				
				foreach my $rec_data ( @rec_data ) {
					my $name         = $rec_data->{'title'};
					my $episode      = $rec_data->{'episode_title'};
					my $cid          = $rec_data->{'cid'};
					my $record_start = $rec_data->{'start'};
					my $image        = $rec_data->{'image_url'};
					my $rid          = $rec_data->{'id'};
					
					$record_start    =~ s/T/ /g;
					$record_start    =~ s/Z//g;
					$record_start    =~ s/-/\//g;
					$name            =~ s/,/ /g;
					$name            =~ s/-/_/g;
					
					if( defined $episode ) {
						$episode         =~ s/,/ /g;
						$episode         =~ s/-/_/g;
					}
					
					my $record_time = Time::Piece->strptime($record_start, "%Y/%m/%d %H:%M:%S");
					my $record_local = strftime("%Y/%m/%d %H:%M:%S", localtime($record_time->epoch) );
					my $rec_loc_sec = strftime("%s", localtime($record_time->epoch) );
					
					if( $rec_loc_sec > strftime("%s", localtime() ) ) {
						$name = "[PLANNED] " . $name;
					}
					
					foreach my $ch_groups ( @ch_groups ) {
						my @channels = @{ $ch_groups->{'channels'} };
						
						foreach my $channels ( @channels ) {
							my $chid    = $channels->{'cid'};
							my $cname   = $channels->{'title'};
							
							if( $cid eq $chid ) {
								if( defined $episode ) {
									$rec_m3u = $rec_m3u . "#EXTINF:0001 tvg-id=\"\" group-title=\"Recordings\" tvg-logo=\"" . $image . "\", " . $record_local . " | " . $name . " (" . $episode . ") | " . $cname . "\n";
								} else {
									$rec_m3u = $rec_m3u . "#EXTINF:0001 tvg-id=\"\" group-title=\"Recordings\" tvg-logo=\"" . $image . "\", " . $record_local . " | " . $name . " | " . $cname . "\n";
								}
								
								if( defined $multi ) {
									if( defined $ffmpeg and $multi eq "1" ) {
										$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
									} elsif( defined $ffmpeg and $multi eq "2" ) {
										$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
									} elsif( defined $ffmpeg and $multi eq "3" ) {
										$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
									} elsif( defined $ffmpeg ) {
										$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
									} elsif( $multi eq "1" ) {
										$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\n";
									} elsif( $multi eq "2" ) {
										$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\n";
									} elsif ( $multi eq "3" ) {
										$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
									} else {
										$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
									}
								} elsif( defined $ffmpeg and defined $dolby and defined $audio2 ) {
									$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
								} elsif( defined $ffmpeg and defined $dolby ) {
									$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
								} elsif( defined $ffmpeg and defined $audio2 ) {
									$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
								} elsif( defined $ffmpeg ) {
									$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
								} elsif( defined $dolby and defined $audio2 ) {
									$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\n";
								} elsif( defined $dolby ) {
									$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\n";
								} elsif( defined $audio2 ) {
									$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\n";
								} else {
									$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
								}	
							}
						}
					}
				}
				
				# CACHE PLAYLIST
				open my $cachedfile, ">", "recordings_m3u:$quality:$platform:cached";
				print $cachedfile "$rec_m3u";
				close $cachedfile;
				
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text', 'Charset' => 'utf8'),
				$response->content(Encode::encode_utf8($rec_m3u));
				$c->send_response($response);
				$c->close;
				
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Recording list sent to client - params: bandwidth=$quality, platform=$platform\n";
				
				# REMOVE CACHED PLAYLIST
				sleep 1;
				unlink "recordings_m3u:$quality:$platform:cached";
				exit;
			
			
			#
			# WILMAA RECORDING LIST
			#
			
			} elsif( $filename eq "recordings.m3u" and $quality =~ /8000|5000|4999|3000|2999|1500/ and $platform =~ /hls|hls5/ and $provider eq "wilmaa.com" and defined $w_user_id ) {
				
				# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
				if( open my $file, "<", "recordings_m3u:$quality:$platform:cached" ) {
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$c->send_file_response("recordings_m3u:$quality:$platform:cached");
					$c->close;
					close $file;
					unlink "recordings_m3u:$quality:$platform:cached";
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Recording list resent to client - params: bandwidth=$quality, platform=$platform\n";
					exit;
				}	
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Loading recordings data\n";
				
				# URLs
				my $playlist_url  = "https://api.wilmaa.com/v3/w/users/$w_user_id/recordings/";
				my $mapping_url   = "https://resources.wilmaa.com/channelsOverview/channelMappings.json";
				
				# RECORDING M3U REQUEST
				my $playlist_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $playlist_request  = HTTP::Request::Common::GET($playlist_url, 'x-wilmaa-session' => $session_token );
				my $playlist_response = $playlist_agent->request($playlist_request);
				
				if( $playlist_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: No permission to use PVR mode\n";
					
					my $response = HTTP::Response->new( 403, 'FORBIDDEN');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: No permission to use PVR mode");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# CHANNEL MAPPING REQUEST
				my $mapping_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $mapping_request  = HTTP::Request::Common::GET($mapping_url);
				my $mapping_response = $mapping_agent->request($mapping_request);
				
				if( $mapping_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Mapping URL: Invalid response\n\n";
					print "RESPONSE:\n\n" . $mapping_response->content . "\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Invalid response on channel request");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# READ JSON
				my $playlist_file;
				my $mapfile;
				
				eval{
					$playlist_file = decode_json($playlist_response->content);
					$mapfile       = decode_json($mapping_response->content);
				};
				
				if( not defined $playlist_file or not defined $mapfile ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Failed to parse JSON file(s) (REC LIST)\n\n";
					
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Failed to parse JSON file (REC LIST)");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# SET UP VALUES
				my @rec_data     = @{ $playlist_file->{'data'} };
				my @dolbysupport = @{ $mapfile->{"extraSettings"}{"dolbyDigital"} };
				
				if( not defined $playlist_file->{'data'}[0]{'epg_title'} ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: No recordings found\n";
					
					my $response = HTTP::Response->new( 404, 'NOT FOUND');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: No recordings found");
					$c->send_response($response);
					$c->close;
					exit;
				} elsif( $playlist_file->{'data'}[0]{'status'} ne "COMPLETED" ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: No completed recordings found\n";
					
					my $response = HTTP::Response->new( 404, 'NOT FOUND');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: No completed recordings found");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				# CREATE RECORDING M3U
				my $rec_m3u   = "#EXTM3U\n";
				
				foreach my $rec_data ( @rec_data ) {
					my $name         = $rec_data->{'epg_title'};
					my $episode      = $rec_data->{'epg_subtitle'};
					my $cname        = $rec_data->{'channel_display_name'};
					my $chid         = $rec_data->{'channel_id'};
					my $record_start = $rec_data->{'start_utc'};
					my $image        = $rec_data->{'epg_img_url'};
					my $rid          = $rec_data->{'id'};
					my $status       = $rec_data->{'status'};
					
					$name            =~ s/,/ /g;
					$name            =~ s/-/_/g;
					
					if( defined $episode ) {
						$episode         =~ s/,/ /g;
						$episode         =~ s/-/_/g;
					}
					
					my $record_local = strftime "%d.%m.%Y %H:%M:%S", localtime($record_start);
					
					if( $status eq "PLANNED" ) {
						$name = "[PLANNED] " . $name;
					}
					
					my $dd_location;
							
					foreach my $dolbysupport ( @dolbysupport ) {
						if( $dolbysupport eq $chid ) {
							$dd_location = "true";
						}
					}
					
					if( defined $episode ) {
						$rec_m3u = $rec_m3u . "#EXTINF:0001 tvg-id=\"\" group-title=\"Recordings\" tvg-logo=\"" . $image . "\", " . $record_local . " | " . $name . " (" . $episode . ") | " . $cname . "\n";
					} else {
						$rec_m3u = $rec_m3u . "#EXTINF:0001 tvg-id=\"\" group-title=\"Recordings\" tvg-logo=\"" . $image . "\", " . $record_local . " | " . $name . " | " . $cname . "\n";
					}
					
					if( defined $multi ) {
						if( defined $ffmpeg and $multi eq "1" and defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
						} elsif( defined $ffmpeg and $multi eq "1" and not defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
						} elsif( defined $ffmpeg and $multi eq "2" and defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
						} elsif( defined $ffmpeg and $multi eq "2" and not defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
						} elsif( defined $ffmpeg and $multi eq "3" ) {
							$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\" -map 0:0 -map 0:1 -map 0:2 -c:a:0 copy -c:a:1 copy -c:v copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
						} elsif( defined $ffmpeg ) {
							$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
						} elsif( $multi eq "1" and defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=1\n";
						} elsif( $multi eq "1" and not defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
						} elsif( $multi eq "2" and defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=2\n";
						} elsif( $multi eq "2" and not defined $dd_location ) {
							$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
						} elsif( $multi eq "3" ) {
							$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&profile=3\n";
						} else {
							$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
						}
					} elsif( defined $ffmpeg and defined $dolby and defined $audio2 and defined $dd_location ) {
						$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
					} elsif( defined $ffmpeg and defined $dolby and defined $dd_location ) {
						$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
					} elsif( defined $ffmpeg and defined $audio2 ) {
						$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
					} elsif( defined $ffmpeg ) {
						$rec_m3u = $rec_m3u .  "pipe://$ffmpeglib -i \"http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\" -vcodec copy -acodec copy -f mpegts -metadata service_name=\"" . $cname . "\" pipe:1\n";
					} elsif( defined $dolby and defined $audio2 and defined $dd_location ) {
						$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true\&audio2=true" . "\n";
					} elsif( defined $dolby and defined $dd_location ) {
						$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&dolby=true" . "\n";
					} elsif( defined $audio2 ) {
						$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\&audio2=true" . "\n";
					} else {
						$rec_m3u = $rec_m3u .  "http://$hostip:$port/index.m3u8?recording=" . $rid ."\&bw=" . $quality . "\&platform=" . $platform . "\n";
					}
				}
					
				# CACHE PLAYLIST
				open my $cachedfile, ">", "recordings_m3u:$quality:$platform:cached";
				print $cachedfile "$rec_m3u";
				close $cachedfile;
				
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text', 'Charset' => 'utf8'),
				$response->content(Encode::encode_utf8($rec_m3u));
				$c->send_response($response);
				$c->close;
				
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Recording list sent to client - params: bandwidth=$quality, platform=$platform\n";
				
				# REMOVE CACHED PLAYLIST
				sleep 1;
				unlink "recordings_m3u:$quality:$platform:cached";
				exit;
					
			} else {
				
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Invalid file request by client\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid file request by client\n");
				$c->send_response($response);
				$c->close;
				exit;
			
			}

		
		#
		# PROVIDE SEGMENTS M3U8
		#
		
		} elsif( defined $zch and defined $zstart and defined $zend and defined $zkeyval and defined $quality and defined $platform ) {
			
			if( $platform eq "hls" ) {
				
				#
				# HLS
				#
			
				my $time  = time()-36;
				my $check = $time/4;
				
				if( defined $time ) {
					
					if( $check =~ m/\.75/ ) {
						my $stamp  = $check*4-3;
						my $stamp2 = $stamp+4;
						my $stamp3 = $stamp+8;
						my $stamp4 = $stamp+12;
						my $stamp5 = $stamp+16;
						my $stamp6 = $stamp+20;
						my $seq   = $stamp/4;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp4.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp5.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp6.ts?z32=$zkeyval";

						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (1) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} elsif( $check =~ m/\.5/ ) {
						
						my $stamp = $check*4-2;
						my $stamp2 = $stamp+4;
						my $stamp3 = $stamp+8;
						my $stamp4 = $stamp+12;
						my $stamp5 = $stamp+16;
						my $stamp6 = $stamp+20;
						my $seq   = $stamp/4;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp4.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp5.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp6.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (2) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} elsif( $check =~ m/\.25/ ) {
						
						my $stamp = $check*4-1;
						my $stamp2 = $stamp+4;
						my $stamp3 = $stamp+8;
						my $stamp4 = $stamp+12;
						my $stamp5 = $stamp+16;
						my $stamp6 = $stamp+20;
						my $seq   = $stamp/4;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp4.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp5.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp6.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (3) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} else {
						
						my $stamp = $check*4;
						my $stamp2 = $stamp+4;
						my $stamp3 = $stamp+8;
						my $stamp4 = $stamp+12;
						my $stamp5 = $stamp+16;
						my $stamp6 = $stamp+20;
						my $seq   = $stamp/4;
						my $date  = localtime($stamp)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:1\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp2.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp3.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp4.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp5.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/$quality/$stamp6.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Segments list sent to client (4) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
					
					}
				
				}
				
			} elsif( $platform eq "hls5" ) {
				
				#
				# HLS5
				# 
				
				my $time  = time()-36;
				my $check = $time/4;
				
				my $audiocodec;
				my $audiobw;
				my $audionum;
						
				my $audioduration1 = "4.011000";
				my $audiodurvalue1 = "4011";
				my $audioduration2 = "3.989000";
				my $audiodurvalue2 = "3989";
				
				if( defined $zaudio ) {
					
					#
					# AUDIO
					#
					
					if( $check =~ m/\.75/ ) {
						
						my $utc = (($check*4000)-3000);
						my $utcvalue = ((($check*4)-3)-36);
						
						my $stamp  = (($check*4000)-3000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						$zaudio =~ /(t_.*)(bw_.*)(num_.*)(\.m3u8)/m;
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
						
						my $audiom3u8;
						
						if( ($seq/2) =~ m/\.5/ ) {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						} else {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						}

						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (1) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} elsif( $check =~ m/\.5/ ) {
						
						my $utc = (($check*4000)-2000);
						my $utcvalue = ((($check*4)-2)-36);
						
						my $stamp  = (($check*4000)-2000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						$zaudio =~ /(t_.*)(bw_.*)(num_.*)(\.m3u8)/m;
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
						
						my $audiom3u8;
						
						if( ($seq/2) =~ m/\.5/ ) {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						} else {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						}
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (2) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} elsif( $check =~ m/\.25/ ) {
						
						my $utc = (($check*4000)-1000);
						my $utcvalue = ((($check*4)-1)-36);
						
						my $stamp  = (($check*4000)-1000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
						
						my $audiom3u8;
						
						if( ($seq/2) =~ m/\.5/ ) {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						} else {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						}
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (3) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} else {
						
						my $utc = ($check*4000);
						my $utcvalue = (($check*4)-36);
						
						my $stamp  = ($check*4000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						$zaudio =~ /(t_.*)(bw_.*)(_)(num_.*)(\.m3u8)/m;
						$audiobw = $2;
						$audionum = $4;
						
						if( $2 =~ m/128/ ) {
							$audiocodec = ".aac";
						} elsif( $2 =~ m/256/ ) {
							$audiocodec = ".eac";
						}
												
						my $audiom3u8;
						
						if( ($seq/2) =~ m/\.5/ ) {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						} else {
							$audiom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp2" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp3" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp4" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration1,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp5" . "_" . $audiobw . "000_d_" . $audiodurvalue1 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n#EXTINF:$audioduration2,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_audio_ts_$stamp6" . "_" . $audiobw . "000_d_" . $audiodurvalue2 . "_" . $audionum . $audiocodec . "?z32=$zkeyval\n";
						}
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($audiom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Audio segments list sent to client (4) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
					
					}
				
				} else {
					
					#
					# VIDEO
					#
					
					if( $check =~ m/\.75/ ) {
						
						my $utc = (($check*4000)-3000);
						my $utcvalue = ((($check*4)-3)-36);
						
						my $stamp  = (($check*4000)-3000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp4" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp5" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp6" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";

						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (1) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} elsif( $check =~ m/\.5/ ) {
						
						my $utc = (($check*4000)-2000);
						my $utcvalue = ((($check*4)-2)-36);
						
						my $stamp  = (($check*4000)-2000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp4" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp5" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp6" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (2) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} elsif( $check =~ m/\.25/ ) {
						
						my $utc = (($check*4000)-1000);
						my $utcvalue = ((($check*4)-1)-36);
						
						my $stamp  = (($check*4000)-1000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp4" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp5" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp6" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (3) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
						
					} else {
						
						my $utc = ($check*4000);
						my $utcvalue = (($check*4)-36);
						
						my $stamp  = ($check*4000)-($zstart*1000);
						my $stamp2 = $stamp+4000;
						my $stamp3 = $stamp+8000;
						my $stamp4 = $stamp+12000;
						my $stamp5 = $stamp+16000;
						my $stamp6 = $stamp+20000;
						my $seq   = $utc/4/1000;
						my $date  = localtime($utcvalue)->strftime('%FT%T.0+00:00');
						
						my $videom3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:$seq\n#EXT-X-PROGRAM-DATE-TIME:$date\n\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp2" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp3" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp4" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp5" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval\n#EXTINF:4,\nhttps://$server-$platform-pvr.zahs.tv/$zch/$zstart/$zend/f_track_video_ts_$stamp6" . "_bw_" . $quality . "000_d_4000_num_0.ts?z32=$zkeyval";
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text'),
						$response->content($videom3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Video segments list sent to client (4) - params: channel=$zch, bandwidth=$quality, platform=$platform\n";
						exit;
					
					}
				
				}
			
			}
		
		#
		# PROVIDE CHANNEL M3U8
		#
		
		} elsif( defined $channel and defined $quality and defined $platform and $tv_mode eq "live" and $provider ne "wilmaa.com" ) {
			
			#
			# ZATTOO CONDITION: HOME
			#
			
			# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
			if( open my $file, "<", "$channel:$quality:$platform:cached" ) {
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text/html'),
				$c->send_file_response("$channel:$quality:$platform:cached");
				$c->close;
				close $file;
				unlink "$channel:$quality:$platform:cached";
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Playlist resent to client\n";
				exit;
			}	
			
			# CHECK CONDITIONS
			if( $platform ne "hls" and  $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Invalid platform\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid platform");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "2999" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Invalid bandwidth\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid bandwidth");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( defined $channel ) {
				
				# REQUEST PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Loading Live URL\n";
				my $live_url = "https://$provider/zapi/watch/live/$channel";
				
				my $live_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				my $cookie_jar    = HTTP::Cookies->new;
				$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/',$provider,443);
				$live_agent->cookie_jar($cookie_jar);
				
				my $live_request;
				
				if( $pin eq "NONE" ) {
					$live_request  = HTTP::Request::Common::POST($live_url, [ 'stream_type' => $platform, 'https_watch_urls' => 'True', 'enable_eac3' => 'true', 'timeshift' => '10800', 'cast_stream_type' => $platform ]);
				} else {
					$live_request  = HTTP::Request::Common::POST($live_url, [ 'stream_type' => $platform, 'https_watch_urls' => 'True', 'enable_eac3' => 'true', 'timeshift' => '10800', 'youth_protection_pin' => $pin, 'cast_stream_type' => $platform ]);
				}
				
				my $live_response = $live_agent->request($live_request);
				
				if( $live_response->is_error ) {
					
					# DO NOT PROCESS: WRONG CHANNEL ID
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Invalid Channel ID\n";
					print "RESPONSE:\n\n" . $live_response->content . "\n\n";
					my $response = HTTP::Response->new( 400, 'BAD REQUEST');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Invalid Channel ID");
					$c->send_response($response);
					$c->close;
					exit;
					
				} else {
					
					my $liveview_file;
					
					eval{
						$liveview_file = decode_json( $live_response->content );
					};
					
					if( not defined $liveview_file ) {
						print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - ERROR: Failed to parse JSON file (LIVE-TV)\n\n";
								
						my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
						$response->header('Content-Type' => 'text'),
						$response->content("API ERROR: Failed to parse JSON file (LIVE-TV)");
						$c->send_response($response);
						$c->close;
						exit;
					}
					
					my $liveview_url = $liveview_file->{'stream'}->{'url'};
				
					# LOAD PLAYLIST URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Loading M3U8\n";
					
					my $livestream_agent  = LWP::UserAgent->new(
						ssl_opts => {
							SSL_verify_mode => $ssl_mode,
							verify_hostname => $ssl_mode,
							SSL_ca_file => Mozilla::CA::SSL_ca_file()  
						},
						agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
					);
					
					my $livestream_request  = HTTP::Request::Common::GET($liveview_url);
					my $livestream_response = $livestream_agent->request($livestream_request);
					
					if( $livestream_response->is_error ) {
						print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - ERROR: Failed to load M3U8\n\n";
						print "RESPONSE:\n\n" . $livestream_response->content . "\n\n";
						my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
						$response->header('Content-Type' => 'text/html'),
						$response->content("API ERROR: Failed to load M3U8");
						$c->send_response($response);
						$c->close;
						exit;
					}
					
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
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Editing M3U8\n";
						$link        =~ /(.*live-$final_quality.*)/m;
						my $link_url = $uri . "/" . $1; 
						
						$link_url =~ s/https:\/\/zattoo-hls-live.akamaized.net/https:\/\/$server-hls-live.zahs.tv/g;
						$link_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls-live.zahs.tv/g;
						
						my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=" . $final_quality . "000\n" . $link_url;
						
						# CACHE PLAYLIST
						open my $cachedfile, ">", "$channel:$quality:$platform:cached";
						print $cachedfile "$m3u8";
						close $cachedfile;
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text/html'),
						$response->content($m3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Playlist sent to client\n";
						
						# REMOVE CACHED PLAYLIST
						sleep 1;
						unlink "$channel:$quality:$platform:cached";
						exit;
					
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
							$final_bandwidth  = "4999000";
							$final_resolution = "1920x1080";
							$final_framerate  = "25";
						} elsif( $quality eq "5000" ) {
							$final_quality_video = "4800";
							$final_bandwidth  = "5000000";
							$final_resolution = "1280x720";
							$final_framerate  = "50";
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
						my $second_final_quality_audio;
						
						# USER WANTS 2 AUDIO STREAMS
						if( defined $multi ) {
							# PROFILE 1: DOLBY 1 + STEREO 2
							if( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "1" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_2";
							# TRY TO USE PROFILE 2 WHEN SECOND STEREO STREAM DOES NOT EXIST: DOLBY 1 + STEREO 1
							} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_0/ and $multi eq "1" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_0";
							# PROFILE 2: DOLBY 1 + STEREO 1
							} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_0/ and $multi eq "2" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_0";
							# PROFILE 3: STEREO 1 + STEREO 2 (DOLBY SUPPORTED)
							} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "3" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_2";
							# PROFILE 3: STEREO 1 + STEREO 2 (NO DOLBY)
							} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_1/ and $multi eq "3" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_1";
							# SELECTED DOLBY PROFILE IS NOT SUPPORTED: TRY TO USE PROFILE 3
							} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_1/ ) {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_1";
								$multi = "3";
							# SELECTED PROFILE IS NOT SUPPORTED + PROFILE 3 IS NOT SUPPORTED: STEREO 1 DUPLICATE
							} else {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_0";
								$multi = "3";
							}
						# USER WANTS 2ND DOLBY AUDIO STREAM
						} elsif( defined $dolby and defined $audio2 ) {
							# AUDIO 2, DOLBY SUPPORTED
							if( $link =~ m/t_track_audio_bw_256_num_3/ and $audio2 eq "true" and $dolby eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_3";
								$final_codec = "avc1.4d4020,ec-3";
							# AUDIO 2, DOLBY SUPPORTED FOR AUDIO 1 ONLY
							} elsif( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" and $dolby eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_2";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							# AUDIO 2, NO DOLBY SUPPORT FOR AUDIO 1
							} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" and $dolby eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_1";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							# AUDIO 2 UNAVAILABLE, DOLBY SUPPORTED
							} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $audio2 eq "true" and $dolby eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3";
							# AUDIO 2 UNAVAILABLE, NO DOLBY SUPPORT
							} else {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							}
						# USER WANTS 1ST DOLBY AUDIO STREAM
						} elsif( defined $dolby ) {
							# AUDIO 1, DOLBY SUPPORTED
							if( $link =~ m/t_track_audio_bw_256_num_1/ and $dolby eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3";
							# AUDIO 1, NO DOLBY SUPPORT
							} else {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							}
						# USER WANTS 2ND STEREO AUDIO STREAM
						} elsif( defined $audio2 ) {
							# AUDIO 2 AVAILABLE, DOLBY SUPPORTED FOR AUDIO 1
							if( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_2";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							# AUDIO 2 AVAILABLE, NO DOLBY SUPPORT FOR AUDIO 1
							} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_1";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							# AUDIO 2 UNAVAILABLE
							} else {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
							}
						# USER WANTS 1ST STEREO AUDIO STREAM
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
						
						# EDIT PLAYLIST
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Editing M3U8\n";
						$link        =~ /(.*)(NAME=")(.*)(",DEFAULT=.*)($final_quality_audio.*?z32=)(.*)"/m;
						my $link_video_url = $uri . "/" . "t_track_video_bw_$final_quality_video" . "_num_0.m3u8?z32=" . $6;
						my $link_audio_url = $uri . "/" . $5 . $6;
						my $language = $3;
						
						if( $language eq "Deutsch" ) {
							$language = "deu";
						} elsif( $language eq "English" ) {
							$language = "eng";
						} elsif( $language eq "Français" ) {
							$language = "fra";
						} elsif( $language eq "Italiano" ) {
							$language = "ita";
						} elsif( $language eq "Español") {
							$language = "spa";
						} elsif( $language eq "Português" ) {
							$language = "por";
						} elsif( $language eq "Türkçe" ) {
							$language = "tur";
						} else {
							$language = "mis";
						}
						
						my $second_link_audio_url;
						my $second_language;
						if( defined $multi and defined $second_final_quality_audio ) {
							$link        =~ /(.*)(NAME=")(.*)(",DEFAULT=.*)($second_final_quality_audio.*?z32=)(.*)"/m;
							$second_link_audio_url = $uri . "/" . $5 . $6;
							$second_language       = $3;
							
							if( $second_language eq "Deutsch" ) {
								$second_language = "deu";
							} elsif( $second_language eq "English" ) {
								$second_language = "eng";
							} elsif( $second_language eq "Français" ) {
								$second_language = "fra";
							} elsif( $second_language eq "Italiano" ) {
								$second_language = "ita";
							} elsif( $second_language eq "Español") {
								$second_language = "spa";
							} elsif( $second_language eq "Português" ) {
								$second_language = "por";
							} elsif( $second_language eq "Türkçe" ) {
								$second_language = "tur";
							} else {
								$second_language = "mis";
							}
						}
						
						$link_video_url =~ s/https:\/\/zattoo-hls5-live.akamaized.net/https:\/\/$server-hls5-live.zahs.tv/g;
						$link_video_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-live.zahs.tv/g;
						
						$link_audio_url =~ s/https:\/\/zattoo-hls5-live.akamaized.net/https:\/\/$server-hls5-live.zahs.tv/g;
						$link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-live.zahs.tv/g;
						
						if( defined $multi and defined $second_link_audio_url ) {
							$second_link_audio_url =~ s/https:\/\/zattoo-hls5-live.akamaized.net/https:\/\/$server-hls5-live.zahs.tv/g;
							$second_link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-live.zahs.tv/g;
						}
						
						my $m3u8;
						if( defined $multi ) {
							$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$second_language\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"$second_language\",URI=\"$second_link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
						} else {
							$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
						}
						
						# CACHE PLAYLIST
						open my $cachedfile, ">", "$channel:$quality:$platform:cached";
						print $cachedfile "$m3u8";
						close $cachedfile;
						
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text/html'),
						$response->content($m3u8);
						$c->send_response($response);
						$c->close;
						
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Playlist sent to client\n";
						
						# REMOVE CACHED PLAYLIST
						sleep 1;
						unlink "$channel:$quality:$platform:cached";
						exit;
						
					}
				
				}
			
			}
		
		} elsif( defined $channel and defined $quality and defined $platform and $tv_mode eq "pvr" and $provider ne "wilmaa.com" ) {
			
			#
			# ZATTOO CONDITION: WORLDWIDE
			#
			
			# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
			if( open my $file, "<", "$channel:$quality:$platform:cached" ) {
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text/html'),
				$c->send_file_response("$channel:$quality:$platform:cached");
				$c->close;
				close $file;
				unlink "$channel:$quality:$platform:cached";
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Playlist resent to client\n";
				exit;
			}	
			
			# LOAD EPG
			print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Requesting EPG\n";
			my $start   = time()-300;
			my $stop    = time()-300;
			my $epg_url = "https://$provider/zapi/v3/cached/$powerid/guide?start=$start&end=$stop";
			
			my $epg_agent = LWP::UserAgent->new(
				ssl_opts => {
					SSL_verify_mode => $ssl_mode,
					verify_hostname => $ssl_mode,
					SSL_ca_file => Mozilla::CA::SSL_ca_file()  
				},
				agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
			);
			
			my $cookie_jar    = HTTP::Cookies->new;
			$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/',$provider,443);
			$epg_agent->cookie_jar($cookie_jar);

			my $epg_request  = HTTP::Request::Common::GET($epg_url);
			my $epg_response = $epg_agent->request($epg_request);
			
			if( $epg_response->is_error ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to load EPG data\n\n";
				print "RESPONSE:\n\n" . $epg_response->content . "\n\n";
				my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Failed to load EPG data");
				$c->send_response($response);
				$c->close;
				exit;
			}
				
			# READ JSON
			my $epg_file;
			
			eval{
				$epg_file = decode_json($epg_response->content);
			};
			
			if( not defined $epg_file ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to parse JSON file (EPG)\n\n";
					
				my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
				$response->header('Content-Type' => 'text'),
				$response->content("API ERROR: Failed to parse JSON file (EPG)");
				$c->send_response($response);
				$c->close;
				exit;
			}
			
			my $rec_id   = $epg_file->{'channels'}{$channel}[0]{'id'};
			
			# CHECK CONDITIONS
			if( not defined $rec_id ) {
				
				# DO NOT PROCESS: WRONG CHANNEL ID / NO EPG AVAILABLE
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Invalid channel ID / no EPG available\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid Channel ID");
				$c->send_response($response);
				$c->close;
				exit;
				
			} elsif( $platform ne "hls" and  $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Invalid platform\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid platform");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "2999" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Invalid bandwidth\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid bandwidth");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( defined $channel ) {
			
				# ADD RECORDING
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Add recording\n";
				my $recadd_url = "https://$provider/zapi/playlist/program";
				
				my $recadd_agent  = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				$recadd_agent->cookie_jar($cookie_jar);

				my $recadd_request  = HTTP::Request::Common::POST($recadd_url, ['program_id' => $rec_id, 'series' => 'false', 'series_force' => 'false' ]);
				my $recadd_response = $recadd_agent->request($recadd_request);
				
				if( $recadd_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to add recording\n\n";
					print "RESPONSE:\n\n" . $recadd_response->content . "\n\n";
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Failed to add recording");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				my $rec_file;
				
				eval{
					$rec_file = decode_json( $recadd_response->content );
				};
				
				if( not defined $rec_file ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to parse JSON file (PVR-TV 1)\n\n";
							
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Failed to parse JSON file (PVR-TV 1)");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				my $rec_fid  = $rec_file->{"recording"}->{"id"};
				my $error_response;
				
				# LOAD RECORDING URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Loading PVR URL\n";
				my $recview_url = "https://$provider/zapi/watch/recording/$rec_fid";
				
				my $recview_agent  = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				$recview_agent->cookie_jar($cookie_jar);

				my $recview_request;
				
				if( $pin eq "NONE" ) {
					$recview_request  = HTTP::Request::Common::POST($recview_url, ['stream_type' => $platform, 'enable_eac3' => 'true', 'https_watch_urls' => 'True', 'cast_stream_type' => $platform ]);
				} else {
					$recview_request  = HTTP::Request::Common::POST($recview_url, ['stream_type' => $platform, 'enable_eac3' => 'true', 'https_watch_urls' => 'True', 'youth_protection_pin' => $pin, 'cast_stream_type' => $platform ]);
				}
				
				my $recview_response = $recview_agent->request($recview_request);
				
				my $link;
				my $uri;
				my $ch;
				
				if( $recview_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to load recording URL\n\n";
					print "RESPONSE:\n\n" . $recview_response->content . "\n\n";
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Failed to load recording URL");
					$c->send_response($response);
					$c->close;
					$error_response = "true";
					
				} else {
				
					my $recview_file;
					
					eval{
						$recview_file = decode_json( $recview_response->content );
					};
					
					if( not defined $recview_file ) {
						print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to parse JSON file (PVR-TV 2)\n\n";
								
						my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
						$response->header('Content-Type' => 'text'),
						$response->content("API ERROR: Failed to parse JSON file (PVR-TV 2)");
						$c->send_response($response);
						$c->close;
						exit;
					}
					
					my $rec_url = $recview_file->{'stream'}->{'url'};
					
					# LOAD PLAYLIST URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Loading M3U8\n";
					
					my $recurl_agent  = LWP::UserAgent->new(
						ssl_opts => {
							SSL_verify_mode => $ssl_mode,
							verify_hostname => $ssl_mode,
							SSL_ca_file => Mozilla::CA::SSL_ca_file()  
						},
						agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
					);
					
					my $recurl_request  = HTTP::Request::Common::GET($rec_url);
					my $recurl_response = $recurl_agent->request($recurl_request);
					
					if( $recurl_response->is_error ) {
						print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to load M3U8\n\n";
						print "RESPONSE:\n\n" . $recurl_response->content . "\n\n";
						my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
						$response->header('Content-Type' => 'text/html'),
						$response->content("API ERROR: Failed to load M3U8 (PVR Live)");
						$c->send_response($response);
						$c->close;
						$error_response = "true";
					}
					
					$link = $recurl_response->content;
					$uri  = $recurl_response->base;
					$ch   = $recurl_response->base;
					
					if( defined $link and defined $uri and defined $ch ) {
						$uri     =~ s/(.*)(\/.*.m3u8.*)/$1/g;
						$ch      =~ s/.*\.tv\///g;
						$ch      =~ s/\/.*//g;
					}
				
				}
				
				# REMOVE RECORDING
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Remove recording\n";
				my $recdel_url = "https://$provider/zapi/playlist/remove";
				
				my $recdel_agent  = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
				
				$recdel_agent->cookie_jar($cookie_jar);

				my $recdel_request  = HTTP::Request::Common::POST($recdel_url, ['recording_id' => $rec_fid ]);
				my $recdel_response = $recdel_agent->request($recdel_request);
					
				if( $recdel_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to remove recording - please delete it manually\n\n";
					print "RESPONSE:\n\n" . $recdel_response->content . "\n\n";
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Failed to remove recording - please delete it manually");
					$c->send_response($response);
					$c->close;
					exit;
				}
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Recording removed\n";
				
				if( defined $error_response ) {
					exit;
				}
			
				# EDIT PLAYLIST URL
				if( $platform eq "hls" ) {
					
					#
					# HLS
					#
					
					# GET SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Loading segments file\n";
					
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
					my $link_agent  = LWP::UserAgent->new(
						ssl_opts => {
							SSL_verify_mode => $ssl_mode,
							verify_hostname => $ssl_mode,
							SSL_ca_file => Mozilla::CA::SSL_ca_file()  
						},
						agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
					);
					
					my $link_request  = HTTP::Request::Common::GET($link_url);
					my $link_response = $link_agent->request($link_request);
						
					if( $link_response->is_error ) {
						print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - ERROR: Failed to load segments M3U8\n\n";
						print "RESPONSE:\n\n" . $link_response->content . "\n\n";
						my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
						$response->header('Content-Type' => 'text/html'),
						$response->content("API ERROR: Failed to load segments M3U8");
						$c->send_response($response);
						$c->close;
						exit;
					}
						
					my $key   = $link_response->content;
					my $start = $uri;
					my $end   = $1;
					$end      =~ s/\/$final_quality.m3u8.*//g;
					$start    =~ s/(.*\/)(.*)/$2/g;

					$key     =~ /($final_quality\/$2.ts\?z32=.*)/m;
					my $keyval  = $1;
					$keyval  =~ s/.*z32=//g;
						
					# EDIT SEGMENTS URL
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Editing segments file\n";
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=$final_quality" . "000\n" . "http://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality\&platform=hls\&zkey=$keyval";
					
					# CACHE PLAYLIST
					open my $cachedfile, ">", "$channel:$quality:$platform:cached";
					print $cachedfile "$m3u8";
					close $cachedfile;
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Playlist sent to client\n";
					
					# REMOVE CACHED PLAYLIST
					sleep 1;
					unlink "$channel:$quality:$platform:cached";
					exit;
					
				} elsif( $platform eq "hls5" ) {
						
					#
					# HLS5
					#
						
					# CREATE SEGMENTS M3U8
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Creating segments M3U8\n";
						
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
						$final_bandwidth  = "4999000";
						$final_resolution = "1920x1080";
						$final_framerate  = "25";
					} elsif( $quality eq "5000" ) {
						$final_quality_video = "4800";
						$final_bandwidth  = "5000000";
						$final_resolution = "1280x720";
						$final_framerate  = "50";
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
					my $second_final_quality_audio;
					
					# USER WANTS 2 AUDIO STREAMS
					if( defined $multi ) {
						# PROFILE 1: DOLBY 1 + STEREO 2
						if( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "1" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_2";
						# TRY TO USE PROFILE 2 WHEN SECOND STEREO STREAM DOES NOT EXIST: DOLBY 1 + STEREO 1
						} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_0/ and $multi eq "1" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
						# PROFILE 2: DOLBY 1 + STEREO 1
						} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_0/ and $multi eq "2" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
						# PROFILE 3: STEREO 1 + STEREO 2 (DOLBY SUPPORTED)
						} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "3" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_2";
						# PROFILE 3: STEREO 1 + STEREO 2 (NO DOLBY SUPPORT)
						} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_1/ and $multi eq "3" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_1";
						# SELECTED DOLBY PROFILE IS NOT SUPPORTED: TRY TO USE PROFILE 3
						} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_1/ ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_1";
						# SELECTED PROFILE IS NOT SUPPORTED + PROFILE 3 IS NOT SUPPORTED: STEREO 1 DUPLICATE
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
						}
					# USER WANTS 2ND DOLBY AUDIO STREAM
					} elsif( defined $dolby and defined $audio2 ) {
						# AUDIO 2, DOLBY SUPPORTED
						if( $link =~ m/t_track_audio_bw_256_num_3/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_3";
							$final_codec = "avc1.4d4020,ec-3";
						# AUDIO 2, DOLBY SUPPORTED FOR AUDIO 1 ONLY
						} elsif( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_2";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2, NO DOLBY SUPPORT FOR AUDIO 1
						} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_1";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2 UNAVAILABLE, DOLBY SUPPORTED
						} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3";
						# AUDIO 2 UNAVAILABLE, NO DOLBY SUPPORT
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
					# USER WANTS 1ST DOLBY AUDIO STREAM
					} elsif( defined $dolby ) {
						# AUDIO 1, DOLBY SUPPORTED
						if( $link =~ m/t_track_audio_bw_256_num_1/ and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3";
						# AUDIO 1, NO DOLBY SUPPORT
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
					# USER WANTS 2ND STEREO AUDIO STREAM
					} elsif( defined $audio2 ) {
						# AUDIO 2, DOLBY SUPPORTED FOR AUDIO 1
						if( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_2";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2, NO DOLBY SUPPORT FOR AUDIO 1
						} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_1";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2 UNAVAILABLE
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
					# USER WANTS 1ST STEREO AUDIO STREAM
					} else {
						$final_quality_audio = "t_track_audio_bw_128_num_0";
						$final_codec = "avc1.4d4020,mp4a.40.2";
					}
						
					$uri         =~ s/.*\.tv\///g;
					$uri         =~ s/.*\.net\///g;
					$uri         =~ /(.*)\/(.*)\/(.*)/m;
						
					my $ch          = $1;
					my $start       = $2;
					my $end         = $3;
						
					$link        =~ /(.*)(NAME=")(.*)(",DEFAULT.*)($final_quality_audio.*)(\?z32=)(.*)"/m;
					
					my $language = $3;
					
					if( $language eq "Deutsch" ) {
						$language = "deu";
					} elsif( $language eq "English" ) {
						$language = "eng";
					} elsif( $language eq "Français" ) {
						$language = "fra";
					} elsif( $language eq "Italiano" ) {
						$language = "ita";
					} elsif( $language eq "Español") {
						$language = "spa";
					} elsif( $language eq "Português" ) {
						$language = "por";
					} elsif( $language eq "Türkçe" ) {
						$language = "tur";
					} else {
						$language = "mis";
					}
					
					my $audio    = $5;
					my $keyval   = $7;
					
					my $second_language;
					my $second_audio;
					my $second_keyval;
					
					if( defined $multi and defined $second_final_quality_audio ) {
						$link        =~ /(.*)(NAME=")(.*)(",DEFAULT.*)($second_final_quality_audio.*)(\?z32=)(.*)"/m;
						
						$second_language = $3;
						
						if( $second_language eq "Deutsch" ) {
							$second_language = "deu";
						} elsif( $second_language eq "English" ) {
							$second_language = "eng";
						} elsif( $second_language eq "Français" ) {
							$second_language = "fra";
						} elsif( $second_language eq "Italiano" ) {
							$second_language = "ita";
						} elsif( $second_language eq "Español") {
							$second_language = "spa";
						} elsif( $second_language eq "Português" ) {
							$second_language = "por";
						} elsif( $second_language eq "Türkçe" ) {
							$second_language = "tur";
						} else {
							$second_language = "mis";
						}
							
						$second_audio    = $5;
						$second_keyval   = $7;
					}
						
					my $m3u8;
					if( defined $multi ) {
						$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"http://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality_video\&audio=$audio\&platform=hls5\&zkey=$keyval\"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$second_language\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"$second_language\",URI=\"http://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality_video\&audio=$second_audio\&platform=hls5\&zkey=$second_keyval\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\nhttp://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality_video\&platform=hls5\&zkey=$keyval";
					} else {
						$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"http://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality_video\&audio=$audio\&platform=hls5\&zkey=$keyval\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\nhttp://$hostip:$port/index.m3u8?ch=$ch\&start=$start\&end=$end\&zid=$rec_fid\&bw=$final_quality_video\&platform=hls5\&zkey=$keyval";
					}
					
					# CACHE PLAYLIST
					open my $cachedfile, ">", "$channel:$quality:$platform:cached";
					print $cachedfile "$m3u8";
					close $cachedfile;
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "PVR-TV $channel | $quality | $platform - Playlist sent to client\n";
					
					# REMOVE CACHED PLAYLIST
					sleep 1;
					unlink "$channel:$quality:$platform:cached";
					exit;
					
				}
			
			}
			
		} elsif( defined $channel and defined $quality and defined $platform and $tv_mode eq "live" and $provider eq "wilmaa.com" and $tv_mode eq "live" ) {
			
			#
			# WILMAA CONDITION: HOME
			#		
			
			# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
			if( open my $file, "<", "$channel:$quality:$platform:cached" ) {
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text/html'),
				$c->send_file_response("$channel:$quality:$platform:cached");
				$c->close;
				close $file;
				unlink "$channel:$quality:$platform:cached";
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Playlist resent to client\n";
				exit;
			}	
				
			# CHECK CONDITIONS
			if( $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Invalid platform\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid platform");
				$c->send_response($response);
				$c->close;
				exit;
				
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "2999" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Invalid bandwidth\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid bandwidth");
				$c->send_response($response);
				$c->close;
				exit;
				
			} elsif( defined $channel ) {
					
				# REQUEST PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Loading Live URL\n";
				my $live_url = "https://streams.wilmaa.com/m3u8/get?channelId=$channel";
				
				my $live_agent = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
					
				my $live_request  = HTTP::Request::Common::GET($live_url);
				my $live_response = $live_agent->request($live_request);
					
				if( $live_response->is_error ) {
					
					# DO NOT PROCESS: WRONG CHANNEL ID
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Invalid Channel ID\n";
					print "RESPONSE:\n\n" . $live_response->content . "\n\n";
					my $response = HTTP::Response->new( 400, 'BAD REQUEST');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Invalid Channel ID");
					$c->send_response($response);
					$c->close;
					exit;
						
				} else {
					
					my $link  = $live_response->content;
					my $link2 = $live_response->content;
					my $uri   = $live_response->base;
						
					$uri     =~ s/(.*)(\/.*.m3u8.*)/$1/g;
						
					if( $platform eq "hls5" ) {
						
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
							$final_bandwidth  = "4999000";
							$final_resolution = "1920x1080";
							$final_framerate  = "25";
						} elsif( $quality eq "5000" ) {
							$final_quality_video = "4800";
							$final_bandwidth  = "5000000";
							$final_resolution = "1280x720";
							$final_framerate  = "50";
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
							
						# SET FINAL AUDIO CODEC + LANGUAGE
						my $final_quality_audio;
						my $final_codec;
						my $second_final_quality_audio;
						my $language;
						my $second_language;
						
						# USER WANTS 2 AUDIO STREAMS
						if( defined $multi ) {
							# PROFILE 1: DOLBY 1 + STEREO 2
							if( $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "1" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_2";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
								$second_language = $3;
							# TRY TO USE PROFILE 2 WHEN SECOND STEREO STREAM DOES NOT EXIST: DOLBY 1 + STEREO 1
							} elsif( $multi eq "1" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_0";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$second_language = $3;
							# PROFILE 2: DOLBY 1 + STEREO 1
							} elsif( $multi eq "2" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_0";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$second_language = $3;
							# PROFILE 3: STEREO 1 + STEREO 2 (DOLBY SUPPORTED)
							} elsif( $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "3" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_2";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
								$second_language = $3;
							# PROFILE 3: STEREO 1 + STEREO 2 (NO DOLBY SUPPORT)
							} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $multi eq "3" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_1";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_1.*)/m;
								$second_language = $3;
							# SELECTED PROFILE IS NOT SUPPORTED + PROFILE 3 IS NOT SUPPORTED: STEREO 1 DUPLICATE
							} else {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$second_final_quality_audio = "t_track_audio_bw_128_num_0";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$second_language = $3;
							}
						# USER WANTS 2ND DOLBY AUDIO STREAM
						} elsif( defined $dolby and defined $audio2 ) {
							# AUDIO 2, DOLBY SUPPORTED
							if( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" and $dolby eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_256_num_3";
								$final_codec = "avc1.4d4020,ec-3";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
								$language = $3;
							# AUDIO 2 UNAVAILABLE, DOLBY SUPPORTED
							} else {
								$final_quality_audio = "t_track_audio_bw_256_num_1";
								$final_codec = "avc1.4d4020,ec-3";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
							}
						# USER WANTS 1ST DOLBY AUDIO STREAM
						} elsif( defined $dolby ) {
							# AUDIO 1, DOLBY SUPPORTED
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
						# USER WANTS 2ND STEREO AUDIO STREAM
						} elsif( defined $audio2 ) {
							# AUDIO 2, DOLBY SUPPORTED
							if( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_2";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
								$language = $3;
							# AUDIO 2, NO DOLBY SUPPORT
							} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" ) {
								$final_quality_audio = "t_track_audio_bw_128_num_1";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_1.*)/m;
								$language = $3;
							# AUDIO 2 UNAVAILABLE
							} else {
								$final_quality_audio = "t_track_audio_bw_128_num_0";
								$final_codec = "avc1.4d4020,mp4a.40.2";
								$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
								$language = $3;
							}
						# USER WANTS 1ST STEREO AUDIO STREAM
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
						}
							
						# EDIT PLAYLIST
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Editing M3U8\n";
						$link        =~ /(.*)(t_track_audio_bw_128_num_0)(.*?z32=)(.*)"/m;
						my $link_video_url = $uri . "/" . "t_track_video_bw_$final_quality_video" . "_num_0.m3u8?z32=" . $4;
						my $link_audio_url = $uri . "/" . $final_quality_audio . $3 . $4;
						
						my $second_link_audio_url;
						if( defined $multi and defined $second_final_quality_audio ) {
							$link        =~ /(.*)(t_track_audio_bw_128_num_0)(.*?z32=)(.*)"/m;
							$second_link_audio_url = $uri . "/" . $second_final_quality_audio . $3 . $4;
						}
							
						$link_video_url =~ s/https:\/\/zattoo-hls5-live.akamaized.net/https:\/\/$server-hls5-live.zahs.tv/g;
						$link_video_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-live.zahs.tv/g;
							
						$link_audio_url =~ s/https:\/\/zattoo-hls5-live.akamaized.net/https:\/\/$server-hls5-live.zahs.tv/g;
						$link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-live.zahs.tv/g;
						
						if( defined $multi and defined $second_link_audio_url ) {
							$second_link_audio_url =~ s/https:\/\/zattoo-hls5-live.akamaized.net/https:\/\/$server-hls5-live.zahs.tv/g;
							$second_link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-live.zahs.tv/g;
						}
						
						if( $language eq "Deutsch" ) {
							$language = "deu";
						} elsif( $language eq "English" ) {
							$language = "eng";
						} elsif( $language eq "Français" ) {
							$language = "fra";
						} elsif( $language eq "Italiano" ) {
							$language = "ita";
						} elsif( $language eq "Español") {
							$language = "spa";
						} elsif( $language eq "Português" ) {
							$language = "por";
						} elsif( $language eq "Türkçe" ) {
							$language = "tur";
						} else {
							$language = "mis";
						}
						
						if( defined $second_language ) {
							if( $second_language eq "Deutsch" ) {
								$second_language = "deu";
							} elsif( $second_language eq "English" ) {
								$second_language = "eng";
							} elsif( $second_language eq "Français" ) {
								$second_language = "fra";
							} elsif( $second_language eq "Italiano" ) {
								$second_language = "ita";
							} elsif( $second_language eq "Español") {
								$second_language = "spa";
							} elsif( $second_language eq "Português" ) {
								$second_language = "por";
							} elsif( $second_language eq "Türkçe" ) {
								$second_language = "tur";
							} else {
								$second_language = "mis";
							}
						}
						
						my $m3u8;
						if( defined $multi ) {
							$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$second_language\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"$second_language\",URI=\"$second_link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
						} else {
							$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
						}
						
						# CACHE PLAYLIST
						open my $cachedfile, ">", "$channel:$quality:$platform:cached";
						print $cachedfile "$m3u8";
						close $cachedfile;
							
						my $response = HTTP::Response->new( 200, 'OK');
						$response->header('Content-Type' => 'text/html'),
						$response->content($m3u8);
						$c->send_response($response);
						$c->close;
							
						print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "LIVE-TV $channel | $quality | $platform - Playlist sent to client\n";
							
						# REMOVE CACHED PLAYLIST
						sleep 1;
						unlink "$channel:$quality:$platform:cached";
						exit;
						
					}
					
				}
			
			}	
			
		
		#
		# PROVIDE ZATTOO RECORDING M3U8
		#
		
		} elsif( defined $rec_ch and defined $quality and defined $platform and $provider ne "wilmaa.com" ) {
			
			# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
			if( open my $file, "<", "$rec_ch:$quality:$platform:cached" ) {
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text/html'),
				$c->send_file_response("$rec_ch:$quality:$platform:cached");
				$c->close;
				close $file;
				unlink "$rec_ch:$quality:$platform:cached";
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Playlist resent to client\n";
				exit;
			}	
			
			print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Loading PVR URL\n";
			my $recchview_url = "https://$provider/zapi/watch/recording/$rec_ch";
				
			my $recchview_agent  = LWP::UserAgent->new(
				ssl_opts => {
					SSL_verify_mode => $ssl_mode,
					verify_hostname => $ssl_mode,
					SSL_ca_file => Mozilla::CA::SSL_ca_file()  
				},
				agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
			);
			
			my $cookie_jar    = HTTP::Cookies->new;
			$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/',$provider,443);
			$recchview_agent->cookie_jar($cookie_jar);
			
			my $recchview_request;
			
			if( $pin eq "NONE" ) {
				$recchview_request  = HTTP::Request::Common::POST($recchview_url, ['stream_type' => $platform, 'enable_eac3' => 'true', 'https_watch_urls' => 'True', 'cast_stream_type' => $platform ]);
			} else {
				$recchview_request  = HTTP::Request::Common::POST($recchview_url, ['stream_type' => $platform, 'enable_eac3' => 'true', 'https_watch_urls' => 'True', 'youth_protection_pin' => $pin, 'cast_stream_type' => $platform ]);
			}
			
			my $recchview_response = $recchview_agent->request($recchview_request);
			
			# CHECK CONDITIONS
			if( $recchview_response->is_error ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Invalid recording ID\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid recording ID");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( $platform ne "hls" and  $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Invalid platform\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid platform");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "2999" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Invalid bandwidth\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid bandwidth");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( defined $rec_ch ) {
				
				my $recchview_file;
				
				eval{
					$recchview_file = decode_json( $recchview_response->content );
				};
				
				if( not defined $recchview_file ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $channel | $quality | $platform - ERROR: Failed to parse JSON file (REC)\n\n";
							
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Failed to parse JSON file (REC)");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				my $recch_url = $recchview_file->{'stream'}->{'url'};
					
				# LOAD PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Loading M3U8\n";
				
				my $recchurl_agent  = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
					
				my $recchurl_request  = HTTP::Request::Common::GET($recch_url);
				my $recchurl_response = $recchurl_agent->request($recchurl_request);
				
				if( $recchurl_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Failed to load M3U8\n\n";
					print "RESPONSE:\n\n" . $recchurl_response->content . "\n\n";
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Failed to load M3U8 (PVR REC)");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				my $link  = $recchurl_response->content;
				my $link2 = $recchurl_response->content;
				my $uri   = $recchurl_response->base;
							
				$uri      =~ s/(.*)(\/.*.m3u8.*)/$1/g;
				
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
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Editing M3U8\n";
					$link        =~ /(.*$final_quality\.m3u8.*)/m;
					my $link_url = $uri . "/" . $1;
					
					$link_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls-pvr.zahs.tv/g;
							
					my $m3u8 = "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=" . $final_quality . "000\n" . $link_url;
					
					# CACHE PLAYLIST
					open my $cachedfile, ">", "$rec_ch:$quality:$platform:cached";
					print $cachedfile "$m3u8";
					close $cachedfile;
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
							
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Playlist sent to client\n";
					
					# REMOVE CACHED PLAYLIST
					sleep 1;
					unlink "$rec_ch:$quality:$platform:cached";
					exit;
				
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
						$final_bandwidth  = "4999000";
						$final_resolution = "1920x1080";
						$final_framerate  = "25";
					} elsif( $quality eq "5000" ) {
						$final_quality_video = "4800";
						$final_bandwidth  = "5000000";
						$final_resolution = "1280x720";
						$final_framerate  = "50";
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
					my $second_final_quality_audio;
					
					# USER WANTS 2 AUDIO STREAMS
					if( defined $multi ) {
						# PROFILE 1: DOLBY 1 + STEREO 2
						if( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "1" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_2";
						# TRY TO USE PROFILE 2 WHEN SECOND STEREO STREAM DOES NOT EXIST: DOLBY 1 + STEREO 1
						} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_0/ and $multi eq "1" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
						# PROFILE 2: DOLBY 1 + STEREO 1
						} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $link =~ m/t_track_audio_bw_128_num_0/ and $multi eq "2" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
						# PROFILE 3: STEREO 1 + STEREO 2 (DOLBY SUPPORTED)
						} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "3" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_2";
						# PROFILE 3: STEREO 1 + STEREO 2 (NO DOLBY SUPPORT)
						} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_1/ and $multi eq "3" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_1";
						# SELECTED DOLBY PROFILE IS NOT SUPPORTED: TRY TO USE PROFILE 3
						} elsif( $link =~ m/t_track_audio_bw_128_num_0/ and $link =~ m/t_track_audio_bw_128_num_1/ ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_1";
							$multi = "3";
						# SELECTED PROFILE IS NOT SUPPORTED + PROFILE 3 IS NOT SUPPORTED: STEREO 1 DUPLICATE
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
							$multi = "3";
						}
					# USER WANTS 2ND DOLBY AUDIO STREAM
					} elsif( defined $dolby and defined $audio2 ) {
						# AUDIO 2, DOLBY SUPPORTED
						if( $link =~ m/t_track_audio_bw_256_num_3/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_3";
							$final_codec = "avc1.4d4020,ec-3";
						# AUDIO 2, DOLBY SUPPORT FOR AUDIO 1 ONLY
						} elsif( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_2";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2, NO DOLBY SUPPORT FOR AUDIO 1
						} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_1";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2 UNAVAILABLE, DOLBY SUPPORTED
						} elsif( $link =~ m/t_track_audio_bw_256_num_1/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3";
						# AUDIO 2 UNAVAILABLE, NO DOLBY SUPPORT
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
					# USER WANTS 1ST DOLBY AUDIO STREAM
					} elsif( defined $dolby ) {
						# AUDIO 1, DOLBY SUPPORTED
						if( $link =~ m/t_track_audio_bw_256_num_1/ and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3";
						# AUDIO 1, NO DOLBY SUPPORT
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
					# USER WANTS 2ND STEREO AUDIO STREAM
					} elsif( defined $audio2 ) {
						# AUDIO 2 AVAILABLE, DOLBY SUPPORTED FOR AUDIO 1
						if( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_2";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2 AVAILABLE, NO DOLBY SUPPORT FOR AUDIO 1
						} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_1";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						# AUDIO 2 UNAVAILABLE
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
						}
					# USER WANTS 1ST STEREO AUDIO STREAM
					} else {
						$final_quality_audio = "t_track_audio_bw_128_num_0";
						$final_codec = "avc1.4d4020,mp4a.40.2";
					}
						
					# EDIT PLAYLIST
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Editing M3U8\n";
					$link        =~ /(.*)(NAME=")(.*)(",DEFAULT.*)($final_quality_audio.*?z32=)(.*)"/m;
					my $link_video_url = $uri . "/" . "t_track_video_bw_$final_quality_video" . "_num_0.m3u8?z32=" . $6;
					my $link_audio_url = $uri . "/" . $5 . $6;
					my $language = $3;
						
					if( $language eq "Deutsch" ) {
						$language = "deu";
					} elsif( $language eq "English" ) {
						$language = "eng";
					} elsif( $language eq "Français" ) {
						$language = "fra";
					} elsif( $language eq "Italiano" ) {
						$language = "ita";
					} elsif( $language eq "Español") {
						$language = "spa";
					} elsif( $language eq "Português" ) {
						$language = "por";
					} elsif( $language eq "Türkçe" ) {
						$language = "tur";
					} else {
						$language = "mis";
					}
					
					my $second_link_audio_url;
					my $second_language;
					if( defined $multi and defined $second_final_quality_audio ) {
						$link        =~ /(.*)(NAME=")(.*)(",DEFAULT=.*)($second_final_quality_audio.*?z32=)(.*)"/m;
						$second_link_audio_url = $uri . "/" . $5 . $6;
						$second_language       = $3;
						
						if( $second_language eq "Deutsch" ) {
							$second_language = "deu";
						} elsif( $second_language eq "English" ) {
							$second_language = "eng";
						} elsif( $second_language eq "Français" ) {
							$second_language = "fra";
						} elsif( $second_language eq "Italiano" ) {
							$second_language = "ita";
						} elsif( $second_language eq "Español") {
							$second_language = "spa";
						} elsif( $second_language eq "Português" ) {
							$second_language = "por";
						} elsif( $second_language eq "Türkçe" ) {
							$second_language = "tur";
						} else {
							$second_language = "mis";
						}
					}
					
					$link_video_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-pvr.zahs.tv/g;
					$link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-pvr.zahs.tv/g;
						
					if( defined $multi and defined $second_link_audio_url ) {
						$second_link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-pvr.zahs.tv/g;
					}
					
					my $m3u8;
					if( defined $multi ) {
						$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$second_language\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"$second_language\",URI=\"$second_link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
					} else {
						$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
					}
					
					# CACHE PLAYLIST
					open my $cachedfile, ">", "$rec_ch:$quality:$platform:cached";
					print $cachedfile "$m3u8";
					close $cachedfile;
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Playlist sent to client\n";
					
					# REMOVE CACHED PLAYLIST
					sleep 1;
					unlink "$rec_ch:$quality:$platform:cached";
					exit;
					
				}
			
			}
		
		
		#
		# PROVIDE WILMAA RECORDING M3U8
		#
		
		} elsif( defined $rec_ch and defined $quality and defined $platform and $provider eq "wilmaa.com" and defined $w_user_id ) {
			
			# CHECK IF PLAYLIST HAS BEEN ALREADY SENT
			if( open my $file, "<", "$rec_ch:$quality:$platform:cached" ) {
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text/html'),
				$c->send_file_response("$rec_ch:$quality:$platform:cached");
				$c->close;
				close $file;
				unlink "$rec_ch:$quality:$platform:cached";
					
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Playlist resent to client\n";
				exit;
			}	
			
			print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Loading PVR URL\n";
			my $recchview_url = "https://api.wilmaa.com/v3/w/users/$w_user_id/recordings/$rec_ch/play?https=true";
				
			my $recchview_agent  = LWP::UserAgent->new(
				ssl_opts => {
					SSL_verify_mode => $ssl_mode,
					verify_hostname => $ssl_mode,
					SSL_ca_file => Mozilla::CA::SSL_ca_file()  
				},
				agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
			);
			
			my $recchview_request  = HTTP::Request::Common::GET($recchview_url, 'x-wilmaa-session' => $session_token );
			
			my $recchview_response = $recchview_agent->request($recchview_request);
			
			# CHECK CONDITIONS
			if( $recchview_response->is_error ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Invalid recording ID\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid recording ID");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( $platform ne "hls5" ) {
				
				# DO NOT PROCESS: WRONG PLATFORM
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Invalid platform\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid platform");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( $quality ne "8000" and $quality ne "4999" and $quality ne "5000" and $quality ne "3000" and $quality ne "2999" and $quality ne "1500" ) {
				
				# DO NOT PROCESS: WRONG QUALITY
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Invalid bandwidth\n";
				my $response = HTTP::Response->new( 400, 'BAD REQUEST');
				$response->header('Content-Type' => 'text/html'),
				$response->content("API ERROR: Invalid bandwidth");
				$c->send_response($response);
				$c->close;
				exit;
			
			} elsif( defined $rec_ch ) {
				
				my $recchview_file;
				
				eval{
					$recchview_file = decode_json( $recchview_response->content );
				};
				
				if( not defined $recchview_file ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $channel | $quality | $platform - ERROR: Failed to parse JSON file (REC)\n\n";
							
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text'),
					$response->content("API ERROR: Failed to parse JSON file (REC)");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				my $recch_url = $recchview_file->{'data'}[0]{'play_url'};
					
				# LOAD PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Loading M3U8\n";
				
				# LOAD PLAYLIST URL
				print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Loading M3U8\n";
				
				my $recchurl_agent  = LWP::UserAgent->new(
					ssl_opts => {
						SSL_verify_mode => $ssl_mode,
						verify_hostname => $ssl_mode,
						SSL_ca_file => Mozilla::CA::SSL_ca_file()  
					},
					agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
				);
					
				my $recchurl_request  = HTTP::Request::Common::GET($recch_url);
				my $recchurl_response = $recchurl_agent->request($recchurl_request);
				
				if( $recchurl_response->is_error ) {
					print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Failed to load M3U8\n\n";
					print "RESPONSE:\n\n" . $recchurl_response->content . "\n\n";
					my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
					$response->header('Content-Type' => 'text/html'),
					$response->content("API ERROR: Failed to load M3U8 (PVR REC)");
					$c->send_response($response);
					$c->close;
					exit;
				}
				
				my $link  = $recchurl_response->content;
				my $link2 = $recchurl_response->content;
				my $uri   = $recchurl_response->base;
							
				$uri      =~ s/(.*)(\/.*.m3u8.*)/$1/g;
				
				if( $platform eq "hls5" ) {
						
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
						$final_bandwidth  = "4999000";
						$final_resolution = "1920x1080";
						$final_framerate  = "25";
					} elsif( $quality eq "5000" ) {
						$final_quality_video = "4800";
						$final_bandwidth  = "5000000";
						$final_resolution = "1280x720";
						$final_framerate  = "50";
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
						
					# SET FINAL AUDIO CODEC + LANGUAGE
					my $final_quality_audio;
					my $final_codec;
					my $second_final_quality_audio;
					my $language;
					my $second_language;
					
					# USER WANTS 2 AUDIO STREAMS
					if( defined $multi ) {
						# PROFILE 1: DOLBY 1 + STEREO 2
						if( $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "1" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_2";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
							$second_language = $3;
						# TRY TO USE PROFILE 2 WHEN SECOND STEREO STREAM DOES NOT EXIST: DOLBY 1 + STEREO 1
						} elsif( $multi eq "1" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$second_language = $3;
						# PROFILE 2: DOLBY 1 + STEREO 1
						} elsif( $multi eq "2" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$second_language = $3;
						# PROFILE 3: STEREO 1 + STEREO 2 (DOLBY SUPPORTED)
						} elsif( $link =~ m/t_track_audio_bw_128_num_2/ and $multi eq "3" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_2";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
							$second_language = $3;
						# PROFILE 3: STEREO 1 + STEREO 2 (NO DOLBY SUPPORT)
						} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $multi eq "3" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_1";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_1.*)/m;
							$second_language = $3;
						# SELECTED PROFILE IS NOT SUPPORTED + PROFILE 3 IS NOT SUPPORTED: STEREO 1 DUPLICATE
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$second_final_quality_audio = "t_track_audio_bw_128_num_0";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$second_language = $3;
						}	
					# USER WANTS 2ND DOLBY AUDIO STREAM
					} elsif( defined $dolby and defined $audio2 ) {
						# AUDIO 2, DOLBY SUPPORTED
						if( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" and $dolby eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_256_num_3";
							$final_codec = "avc1.4d4020,ec-3";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
							$language = $3;
						# AUDIO 2 UNAVAILABLE, DOLBY SUPPORTED
						} else {
							$final_quality_audio = "t_track_audio_bw_256_num_1";
							$final_codec = "avc1.4d4020,ec-3";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
						}
					# USER WANTS 1ST DOLBY AUDIO STREAM
					} elsif( defined $dolby ) {
						# AUDIO 1, DOLBY SUPPORTED
						$final_quality_audio = "t_track_audio_bw_256_num_1";
						$final_codec = "avc1.4d4020,ec-3";
						$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
						$language = $3;
					# USER WANTS 2ND STEREO AUDIO STREAM
					} elsif( defined $audio2 ) {
						# AUDIO 2, DOLBY SUPPORTED
						if( $link =~ m/t_track_audio_bw_128_num_2/ and $audio2 eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_2";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_2.*)/m;
							$language = $3;
						# AUDIO 2, NO DOLBY SUPPORT
						} elsif( $link =~ m/t_track_audio_bw_128_num_1/ and $audio2 eq "true" ) {
							$final_quality_audio = "t_track_audio_bw_128_num_1";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_1.*)/m;
							$language = $3;
						# AUDIO 2 UNAVAILABLE
						} else {
							$final_quality_audio = "t_track_audio_bw_128_num_0";
							$final_codec = "avc1.4d4020,mp4a.40.2";
							$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
							$language = $3;
						}
					# USER WANTS 1ST STEREO AUDIO STREAM
					} else {
						$final_quality_audio = "t_track_audio_bw_128_num_0";
						$final_codec = "avc1.4d4020,mp4a.40.2";
						$link =~ /(.*)(NAME=")(.*)(",DEFAULT.*)(t_track_audio_bw_128_num_0.*)/m;
						$language = $3;
					}
						
					# EDIT PLAYLIST
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Editing M3U8\n";
					$link        =~ /(.*)(t_track_audio_bw_128_num_0)(.*?z32=)(.*)"/m;
					my $link_video_url = $uri . "/" . "t_track_video_bw_$final_quality_video" . "_num_0.m3u8?z32=" . $4;
					my $link_audio_url = $uri . "/" . $final_quality_audio . $3 . $4;
					
					my $second_link_audio_url;
					if( defined $multi and defined $second_final_quality_audio ) {
						$link        =~ /(.*)(t_track_audio_bw_128_num_0)(.*?z32=)(.*)"/m;
						$second_link_audio_url = $uri . "/" . $second_final_quality_audio . $3 . $4;
					}
					
					$link_video_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-pvr.zahs.tv/g;
					$link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-pvr.zahs.tv/g;
					
					if( defined $multi and defined $second_link_audio_url ) {
						$second_link_audio_url =~ s/https:\/\/.*zahs.tv/https:\/\/$server-hls5-pvr.zahs.tv/g;
					}
					
					if( $language eq "Deutsch" ) {
						$language = "deu";
					} elsif( $language eq "English" ) {
						$language = "eng";
					} elsif( $language eq "Français" ) {
						$language = "fra";
					} elsif( $language eq "Italiano" ) {
						$language = "ita";
					} elsif( $language eq "Español") {
						$language = "spa";
					} elsif( $language eq "Português" ) {
						$language = "por";
					} elsif( $language eq "Türkçe" ) {
						$language = "tur";
					} else {
						$language = "mis";
					}
						
					if( defined $second_language ) {
						if( $second_language eq "Deutsch" ) {
							$second_language = "deu";
						} elsif( $second_language eq "English" ) {
							$second_language = "eng";
						} elsif( $second_language eq "Français" ) {
							$second_language = "fra";
						} elsif( $second_language eq "Italiano" ) {
							$second_language = "ita";
						} elsif( $second_language eq "Español") {
						$second_language = "spa";
						} elsif( $second_language eq "Português" ) {
							$second_language = "por";
						} elsif( $second_language eq "Türkçe" ) {
							$second_language = "tur";
						} else {
							$second_language = "mis";
						}
					}
					
					my $m3u8;
					if( defined $multi ) {
						$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$second_language\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"$second_language\",URI=\"$second_link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
					} else {
						$m3u8 = "#EXTM3U\n#EXT-X-VERSION:5\n#EXT-X-INDEPENDENT-SEGMENTS\n\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio-group\",NAME=\"$language\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"$language\",URI=\"$link_audio_url\"\n\n#EXT-X-STREAM-INF:BANDWIDTH=$final_bandwidth,CODECS=\"$final_codec\",RESOLUTION=$final_resolution,FRAME-RATE=$final_framerate,AUDIO=\"audio-group\",CLOSED-CAPTIONS=NONE\n$link_video_url";
					}
					
					# CACHE PLAYLIST
					open my $cachedfile, ">", "$rec_ch:$quality:$platform:cached";
					print $cachedfile "$m3u8";
					close $cachedfile;
					
					my $response = HTTP::Response->new( 200, 'OK');
					$response->header('Content-Type' => 'text/html'),
					$response->content($m3u8);
					$c->send_response($response);
					$c->close;
						
					print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "REC $rec_ch | $quality | $platform - Playlist sent to client\n";
					
					# REMOVE CACHED PLAYLIST
					sleep 1;
					unlink "$rec_ch:$quality:$platform:cached";
					exit;
				
				}
			
			}		
		
		
		#
		# REMOVE ZATTOO RECORDING
		#
		
		} elsif( defined $rec_ch and $provider ne "wilmaa.com" and defined $remove) {
			
			print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Removing record\n";
				
			# URL
			my $remove_url   = "https://$provider/zapi/playlist/remove";
				
			# COOKIE
			my $cookie_jar    = HTTP::Cookies->new;
			$cookie_jar->set_cookie(0,'beaker.session.id',$session_token,'/',$provider,443);
			
			# REMOVE REQUEST
			my $remove_agent = LWP::UserAgent->new(
				ssl_opts => {
					SSL_verify_mode => $ssl_mode,
					verify_hostname => $ssl_mode,
					SSL_ca_file => Mozilla::CA::SSL_ca_file()  
				},
				agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
			);
				
			$remove_agent->cookie_jar($cookie_jar);
			my $remove_request  = HTTP::Request::Common::POST($remove_url, [ 'recording_id' => $rec_ch ]);
			my $remove_response = $remove_agent->request($remove_request);
			
			if( $remove_response->is_error ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Remove URL: Invalid response\n\n";
				print "RESPONSE:\n\n" . $remove_response->content . "\n\n";
				
				my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
				$response->header('Content-Type' => 'text'),
				$response->content("API ERROR: Invalid response on remove request");
				$c->send_response($response);
				$c->close;
				exit;
			} elsif( $remove_response->is_success ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "SUCCESS: Recording removed\n\n";
				
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text'),
				$response->content("SUCCESS: Recording removed");
				$c->send_response($response);
				$c->close;
				exit;
			}
			
		
		#
		# REMOVE WILMAA RECORDING
		#
		
		} elsif( defined $rec_ch and $provider eq "wilmaa.com" and defined $w_user_id and defined $remove) {
			
			print "* " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "Removing record\n";
				
			# URL
			my $remove_url   = "https://api.wilmaa.com/v3/w/users/$w_user_id/recordings/$rec_ch";
			
			# REMOVE REQUEST
			my $remove_agent = LWP::UserAgent->new(
				ssl_opts => {
					SSL_verify_mode => $ssl_mode,
					verify_hostname => $ssl_mode,
					SSL_ca_file => Mozilla::CA::SSL_ca_file()  
				},
				agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:54.0) Gecko/20100101 Firefox/72.0"
			);
				
			my $remove_request  = HTTP::Request::Common::DELETE($remove_url, 'x-wilmaa-session' => $session_token );
			my $remove_response = $remove_agent->request($remove_request);
			
			if( $remove_response->is_error ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "ERROR: Remove URL: Invalid response\n\n";
				print "RESPONSE:\n\n" . $remove_response->content . "\n\n";
				
				my $response = HTTP::Response->new( 500, 'INTERNAL SERVER ERROR');
				$response->header('Content-Type' => 'text'),
				$response->content("API ERROR: Invalid response on remove request");
				$c->send_response($response);
				$c->close;
				exit;
			} elsif( $remove_response->is_success ) {
				print "X " . localtime->strftime('%Y-%m-%d %H:%M:%S ') . "SUCCESS: Recording removed\n\n";
				
				my $response = HTTP::Response->new( 200, 'OK');
				$response->header('Content-Type' => 'text'),
				$response->content("SUCCESS: Recording removed");
				$c->send_response($response);
				$c->close;
				exit;
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
			exit;
		}
	}
}
