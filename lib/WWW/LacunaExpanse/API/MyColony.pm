package WWW::LacunaExpanse::API::MyColony;

use Moose;
use Carp;
use Data::Dumper;

extends 'WWW::LacunaExpanse::API::Colony';

my $path = '/body';

has buildings => (is => 'ro', lazy_build => 1);

my @simple_strings  = qw(needs_surface_refresh building_count plots_available happiness happiness_hour
    food_stored food_capacity food_hour energy_stored energy_capacity energy_hour ore_stored
    ore_capacity ore_hour water_stored water_capacity water_hour waste_stored waste_capacity
    waste_hour);
my @date_strings    = qw();
my @other_strings   = qw(incoming_foreign_ships);

for my $attr (@simple_strings, @date_strings, @other_strings) {
    has $attr => (is => 'ro', writer => "_$attr", lazy_build => 1);

    __PACKAGE__->meta()->add_method(
        "_build_$attr" => sub {
            my ($self) = @_;
            $self->update_colony;
            return $self->$attr;
        }
    );
}

# Refresh the object from the Server
#
sub update_colony {
    my ($self) = @_;

    $self->connection->debug(0);
    my $result = $self->connection->call($path, 'get_status',[$self->connection->session_id, $self->id]);
    $self->connection->debug(0);

    my $body = $result->{result}{body};

    $self->simple_strings($body, \@simple_strings);

    $self->date_strings($body, \@date_strings);

    # other strings
    # Incoming Foreign Ships
}


# Get a list of buildings (if any)
#
sub _build_buildings {
    my ($self) = @_;

    my @buildings;

    if ($self->building_count) {
        $self->connection->debug(0);
        my $result = $self->connection->call($path, 'get_buildings',[$self->connection->session_id, $self->id]);
        $self->connection->debug(0);
        my $body = $result->{result}{buildings};
        for my $id (keys %$body) {

            my $hash = $body->{$id};
            my $pending_build;
            if ($hash->{pending_build}) {
                $pending_build = WWW::LacunaExpanse::API::Building::Timer->new({
                    remaining   => $hash->{pending_build}{seconds_remaining},
                    start       => WWW::LacunaExpanse::API::DateTime->from_lacuna_string($hash->{pending_build}{start}),
                    end         => WWW::LacunaExpanse::API::DateTime->from_lacuna_string($hash->{pending_build}{end}),
                });
            }

            my $work;
            if ($hash->{work}) {
                $work = WWW::LacunaExpanse::API::Building::Timer->new({
                    remaining   => $hash->{work}{seconds_remaining},
                    start       => WWW::LacunaExpanse::API::DateTime->from_lacuna_string($hash->{work}{start}),
                    end         => WWW::LacunaExpanse::API::DateTime->from_lacuna_string($hash->{work}{end}),
                });
            }

            my $name = $body->{$id}{name};
            $name =~ s/ //g;

            # Call the Factory to make the Building object
            my $building = WWW::LacunaExpanse::API::BuildingFactory->create(
                $name, {
                    id              => $id,
                    body_id         => $self->id,
                    url             => $hash->{url},
                    colony          => $self,
                    name            => $hash->{name},
                    x               => $hash->{x},
                    y               => $hash->{y},

                    level           => $hash->{level},
                    image           => $hash->{image},
                    efficiency      => $hash->{efficiency},
                    pending_build   => $pending_build,
                    work            => $work,
                }
            );

            push @buildings, $building;
        }
    }
    return \@buildings;
}

# Get co-ordinates of free building spaces (not plots)
#
sub get_free_building_spaces {
    my ($self) = @_;

    my $space_has_building;
    for my $building (@{$self->buildings}) {
        $space_has_building->{$building->x}{$building->y} = $building;
    }
    my @free_spaces;
    for my $x (-5..5) {
        for my $y (-5..5) {
            if (! $space_has_building->{$x}{$y}) {
                push @free_spaces, {x => $x, y => $y};
            }
        }
    }
    return \@free_spaces;
}

# Build a building
#
sub build_a_building {
    my ($self, $name, $x, $y) = @_;

    my $log = Log::Log4perl->get_logger('WWW::LacunaExpanse::API::MyColony');

    my $url = '/' . lc $name;

    my $max_tries = 3;

    TRIES:
    while ($max_tries) {
        # TRY
        eval {
            my $result = $self->connection->call($url, 'build',[$self->connection->session_id, $self->id, $x, $y]);
        };
        # CATCH
        if ($@) {
            my $e = $@;
            if ($e =~ /\(1009\).*no room left in the build queue/) {
                $log->debug("RETRY: ".(4 - $max_tries)." $e");
                $max_tries--;
                # If we only wait 15 seconds, then every second build will fail
                # so waiting longer is better (less RPC wasteage)
                sleep 66;
            }
            else {
                $log->error($e);
                return;
            }
        }
        else {
            last TRIES;
        }
    }
    return 1;
}

# Return the Intelligence Ministry for this colony
#
sub intelligence {
    my ($self) = @_;

    my ($intelligence) = grep {$_->name eq 'Intelligence Ministry'} @{$self->buildings};
    return $intelligence;
}

# Return the (first) space port for this colony
#
sub space_port {
    my ($self) = @_;

    my ($space_port) = grep {$_->name eq 'Space Port'} @{$self->buildings};
    return $space_port;
}

# Return the (first) observatory for this colony
#
sub observatory {
    my ($self) = @_;

    my ($observatory) = grep {$_->name eq 'Observatory'} @{$self->buildings};
    return $observatory;
}

# Return the (only) mercenaries guild for this colony
#
sub mercenaries_guild {
    my ($self) = @_;

    my ($merc_guild) = grep {$_->name eq 'Mercenaries Guild'} @{$self->buildings};
    return $merc_guild;
}

# Return the (first) shipyard for this colony
#
sub shipyard {
    my ($self) = @_;

    my ($shipyard) = grep {$_->name eq 'Shipyard'} @{$self->buildings};
    return $shipyard;
}

# Return the (first) Genetics Lab for this colony
#
sub genetics_lab {
    my ($self) = @_;

    my ($genetics_lab) = grep {$_->name eq 'Genetics Lab'} @{$self->buildings};
    return $genetics_lab;
}

# Return the (first) Archaeology ministry for this colony
#
sub archaeology {
    my ($self) = @_;

    my ($archaeology) = grep {$_->name eq 'Archaeology Ministry'} @{$self->buildings};
    return $archaeology;
}

# Return the Trade Ministry
#
sub trade_ministry {
    my ($self) = @_;

    my ($trade) = grep {$_->name eq 'Trade Ministry'} @{$self->buildings};
    return $trade;
}

# Return the Planetary Command Center
#
sub planetary_command_center {
    my ($self) = @_;

    my ($pcc) = grep {$_->name eq 'Planetary Command Center'} @{$self->buildings};
    return $pcc;
}

# Return the waste henge
#
sub junk_henge_sculpture {
    my ($self) = @_;

    my ($junk_henge) = grep {$_->name eq 'Junk Henge Sculpture'} @{$self->buildings};
    return $junk_henge;
}

# Return all buildings of a particular type
#
sub building_type {
    my ($self, $building_type) = @_;

    my @buildings = grep {$_->name eq $building_type} @{$self->buildings};

    return \@buildings;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
