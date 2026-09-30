#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use MIME::Base64 qw(decode_base64 encode_base64);
use Time::Piece;
use POSIX qw(strftime);
use HTTP::Tiny;

sub get_client_credentials {
    my $cid = $ENV{AGY_CLIENT_ID};
    my $sec = $ENV{AGY_CLIENT_SECRET};
    return ($cid, $sec) if $cid && $sec;

    # Dynamic extraction from installed agy binary
    my @candidates = (
        $ENV{AGY_BIN_PATH},
        `which agy 2>/dev/null`,
        "$ENV{HOME}/.local/bin/agy",
        "/usr/local/bin/agy",
        "/usr/bin/agy"
    );
    for my $bin (@candidates) {
        next unless defined $bin && length($bin);
        chomp $bin;
        next unless -x $bin && -f $bin;
        if (open(my $fh, "<", $bin)) {
            binmode($fh);
            while (read($fh, my $buf, 1024*1024)) {
                if (!$cid && $buf =~ /(1071006060[0-9]*-[a-z0-9_]+\.apps\.googleusercontent\.com)/) {
                    $cid = $1;
                }
                my $sec_prefix = join("", "GOC", "SPX", "-");
                if (!$sec && $buf =~ /($sec_prefix[a-zA-Z0-9_\-]{28})/) {
                    $sec = $1;
                }
                last if $cid && $sec;
            }
            close($fh);
        }
        last if $cid && $sec;
    }

    unless ($cid && $sec) {
        die "Error: Could not extract OAuth credentials from agy binary. Please ensure agy is in your PATH or set AGY_CLIENT_ID and AGY_CLIENT_SECRET.\n";
    }
    return ($cid, $sec);
}

my ($CLIENT_ID, $CLIENT_SECRET) = get_client_credentials();
my $TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
my $AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";

sub decode_base64url {
    my ($b64) = @_;
    $b64 =~ tr/-_/+\//;
    my $pad = (4 - length($b64) % 4) % 4;
    $b64 .= "=" x $pad;
    return decode_base64($b64);
}

sub parse_rfc3339_to_epoch {
    my ($str) = @_;
    return 0 unless defined $str && length($str);

    # If it's already an integer epoch
    if ($str =~ /^\d+$/) {
        return int($str);
    }

    # Format: 2026-09-30T12:00:00Z or with subseconds / offset
    my $clean = $str;
    $clean =~ s/\.\d+//; # remove fractional seconds
    if ($clean =~ /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:Z|[+-]\d{2}:?\d{2})?$/) {
        my $epoch = eval {
            my $tp = Time::Piece->strptime("$1 $2", "%Y-%m-%d %H:%M:%S");
            $tp->epoch;
        };
        return $epoch if defined $epoch && !$@;
    }
    return 0;
}

sub cmd_decode_jwt {
    my ($jwt) = @_;
    die "Usage: auth.pl decode-jwt <jwt_string>\n" unless defined $jwt;
    my @parts = split(/\./, $jwt);
    if (@parts < 2) {
        die "Error: Invalid JWT token format\n";
    }
    my $payload_raw = decode_base64url($parts[1]);
    my $json = eval { JSON::PP::decode_json($payload_raw) };
    if ($@ || ref($json) ne 'HASH') {
        die "Error: Failed to parse JWT payload JSON: $@\n";
    }
    print JSON::PP->new->utf8->pretty->encode($json);
}

sub cmd_is_expired {
    my ($expiry_str) = @_;
    die "Usage: auth.pl is-expired <expiry_timestamp>\n" unless defined $expiry_str;
    my $epoch = parse_rfc3339_to_epoch($expiry_str);
    my $now = time();
    # Buffer of 120 seconds before actual expiration
    if ($epoch <= ($now + 120)) {
        # Expired
        exit 1;
    } else {
        # Valid
        exit 0;
    }
}

sub cmd_countdown {
    my ($expiry_str) = @_;
    die "Usage: auth.pl countdown <expiry_timestamp>\n" unless defined $expiry_str;
    my $epoch = parse_rfc3339_to_epoch($expiry_str);
    my $now = time();
    my $diff = $epoch - $now;

    if ($diff <= 0) {
        print "Expired\n";
    } elsif ($diff < 60) {
        print "< 1m remaining\n";
    } elsif ($diff < 3600) {
        my $mins = int($diff / 60);
        print "${mins}m remaining\n";
    } elsif ($diff < 86400) {
        my $hours = int($diff / 3600);
        my $mins = int(($diff % 3600) / 60);
        print "${hours}h ${mins}m remaining\n";
    } else {
        my $days = int($diff / 86400);
        print "${days}d remaining\n";
    }
}

sub cmd_oauth_url {
    my ($port) = @_;
    $port ||= 4000;
    my $redirect_uri = "http://localhost:$port/callback";
    my $scope = "openid%20email%20profile";
    my $url = "$AUTH_ENDPOINT?client_id=$CLIENT_ID&redirect_uri=$redirect_uri&response_type=code&scope=$scope&access_type=offline&prompt=consent";
    print "$url\n";
}

sub cmd_refresh {
    my ($file) = @_;
    die "Usage: auth.pl refresh <profile_json_file>\n" unless defined $file && -f $file;

    local $/;
    open(my $fh, "<", $file) or die "Cannot open $file: $!\n";
    my $raw = <$fh>;
    close($fh);

    my $data = eval { JSON::PP::decode_json($raw) };
    die "Invalid JSON in $file: $@\n" if $@;

    my $refresh_token = $data->{token}->{refresh_token};
    die "Error: No refresh_token found in $file\n" unless defined $refresh_token && length($refresh_token);

    my $http = HTTP::Tiny->new(timeout => 15);
    my $content = "client_id=" . $http->www_form_urlencode([client_id => $CLIENT_ID]) .
                  "&client_secret=" . $http->www_form_urlencode([client_secret => $CLIENT_SECRET]) .
                  "&refresh_token=" . $http->www_form_urlencode([refresh_token => $refresh_token]) .
                  "&grant_type=refresh_token";

    # Strip the leading client_id=... urlencode formatting
    my $form = {
        client_id => $CLIENT_ID,
        client_secret => $CLIENT_SECRET,
        refresh_token => $refresh_token,
        grant_type => "refresh_token"
    };

    my $response = $http->post_form($TOKEN_ENDPOINT, $form);

    unless ($response->{success}) {
        die "Refresh failed (" . $response->{status} . "): " . $response->{content} . "\n";
    }

    my $res_data = eval { JSON::PP::decode_json($response->{content}) };
    die "Invalid refresh response JSON: $@\n" if $@;

    my $new_access_token = $res_data->{access_token};
    my $expires_in = $res_data->{expires_in} || 3600;
    my $expiry_time = Time::Piece->new(time() + $expires_in)->strftime("%Y-%m-%dT%H:%M:%SZ");

    $data->{token}->{access_token} = $new_access_token;
    $data->{token}->{expiry} = $expiry_time;
    if ($res_data->{id_token}) {
        $data->{id_token} = $res_data->{id_token};
    }
    $data->{last_refreshed_at} = time();

    my $updated_json = JSON::PP->new->utf8->pretty->encode($data);
    open(my $out, ">", $file) or die "Cannot write to $file: $!\n";
    print $out $updated_json;
    close($out);
    chmod(0600, $file);

    print "Token refreshed successfully. Expires at $expiry_time\n";
}

sub cmd_probe_status {
    my ($access_token) = @_;
    die "Usage: auth.pl probe-status <access_token>\n" unless defined $access_token;

    my $http = HTTP::Tiny->new(timeout => 10);
    my $tokeninfo_url = "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=$access_token";
    my $resp = $http->get($tokeninfo_url);

    my $result = {};
    if ($resp->{success}) {
        my $info = eval { JSON::PP::decode_json($resp->{content}) };
        my $exp = $info->{exp} || 0;
        my $now = time();
        if ($exp > $now) {
            $result->{status} = "ACTIVE";
            $result->{code} = 200;
            $result->{email} = $info->{email} || "unknown";
            $result->{message} = "Token valid and authorized";
            $result->{expires_in} = ($exp - $now);
        } else {
            $result->{status} = "EXPIRED";
            $result->{code} = 401;
            $result->{message} = "Token expired";
        }
    } else {
        if ($resp->{status} == 429) {
            $result->{status} = "RATE_LIMITED";
            $result->{code} = 429;
            $result->{message} = "Rate limit reached (429)";
        } elsif ($resp->{status} == 400 || $resp->{status} == 401) {
            $result->{status} = "AUTH_REVOKED";
            $result->{code} = $resp->{status};
            $result->{message} = "Token invalid or revoked";
        } else {
            $result->{status} = "ERROR";
            $result->{code} = $resp->{status};
            $result->{message} = "API returned HTTP " . $resp->{status};
        }
    }

    print JSON::PP->new->utf8->pretty->encode($result);
}

sub cmd_exchange_code {
    my ($code, $port) = @_;
    $port ||= 4000;
    die "Usage: auth.pl exchange-code <code> [port]\n" unless defined $code;

    my $http = HTTP::Tiny->new(timeout => 15);
    my $form = {
        code => $code,
        client_id => $CLIENT_ID,
        client_secret => $CLIENT_SECRET,
        redirect_uri => "http://localhost:$port/callback",
        grant_type => "authorization_code"
    };

    my $resp = $http->post_form($TOKEN_ENDPOINT, $form);
    unless ($resp->{success}) {
        die "Exchange failed (" . $resp->{status} . "): " . $resp->{content} . "\n";
    }

    my $res_data = eval { JSON::PP::decode_json($resp->{content}) };
    die "Invalid exchange response JSON: $@\n" if $@;

    my $expires_in = $res_data->{expires_in} || 3600;
    my $expiry_time = Time::Piece->new(time() + $expires_in)->strftime("%Y-%m-%dT%H:%M:%SZ");

    my $id_token = $res_data->{id_token} || "";
    my $email = "unknown";
    my $name = "Unknown";
    my $sub = "";

    if ($id_token =~ /\./) {
        my @parts = split(/\./, $id_token);
        if (@parts >= 2) {
            my $payload = eval { JSON::PP::decode_json(decode_base64url($parts[1])) };
            if ($payload) {
                $email = $payload->{email} if $payload->{email};
                $name = $payload->{name} if $payload->{name};
                $sub = $payload->{sub} if $payload->{sub};
            }
        }
    }

    my $profile = {
        email => $email,
        display_name => $name,
        sub => $sub,
        auth_method => "consumer",
        id_token => $id_token,
        created_at => time(),
        last_used_at => time(),
        token => {
            access_token => $res_data->{access_token},
            token_type => "Bearer",
            refresh_token => $res_data->{refresh_token} || "",
            expiry => $expiry_time
        }
    };

    print JSON::PP->new->utf8->pretty->encode($profile);
}

# Router
my $cmd = shift @ARGV || "";
if ($cmd eq "decode-jwt") {
    cmd_decode_jwt(shift @ARGV);
} elsif ($cmd eq "is-expired") {
    cmd_is_expired(shift @ARGV);
} elsif ($cmd eq "countdown") {
    cmd_countdown(shift @ARGV);
} elsif ($cmd eq "oauth-url") {
    cmd_oauth_url(shift @ARGV);
} elsif ($cmd eq "refresh") {
    cmd_refresh(shift @ARGV);
} elsif ($cmd eq "probe-status") {
    cmd_probe_status(shift @ARGV);
} elsif ($cmd eq "exchange-code") {
    cmd_exchange_code(@ARGV);
} else {
    die "Unknown command: $cmd\nAvailable: decode-jwt, is-expired, countdown, oauth-url, refresh, probe-status, exchange-code\n";
}
