package Dancer2::Plugin::ProbabilityRoute;
# ABSTRACT: plugin to define behavior with probability matching rules

=head1 DESCRIPTION

This plugin is designed to let you write a Dancer2 application with routes that
match under a given probability for a given user.

This could be used to build A/B Testing routes, for testing the website user's
behavior when exposed to version A or B of your website.

But it can be used to do more, as you can split a route into as many versions
as you like up to 100.

The decision to assign a given version of the route to a user is stable in time,
for a given user. It means a given user will always see the same version of the
route as long as they don't purge their cookies.

=head1 SYNOPSIS

    package myApp;
    use Dancer2;
    use Dancer2::Plugin::ABTest;

    # a basic A/B test (50/50 chances)
    probability_route 50, 'get' => '/test' => sub {
            "A is returned for you";
    };

    probability_route 50, 'get' => '/test' => sub {
            "B is returned for you";
    };

    declare_probability_routes;

    1;
=cut

use strict;
use warnings;
use Dancer2::Plugin;
use Digest::OAT 'oat';
use Carp 'croak';

my $_routes = {};

=method probability_route

Use this keyword to declare a route that gets triggered only under a given
probability.
The sequence is important: the first declaration for a given method/path tuple
is the default version of the route.

Here is an example of a 30, 50, 20 split:

    probability_route 30, 'get', '/' => sub { "30% chances to get there" };
    probability_route 50, 'get', '/' => sub { "50% chances to get there" };
    probability_route 30, 'get', '/' => sub { "20% chances to get there" };

To provide stability for each user, the session ID is used as a pivot, to build
a I<user_score>, which is an number between 0 and 99.

That number can also be used in regular routes or templates to create your own
conditions. See C<probability_user_score> for details.

Note that the sum of all the probability_route statements must equal 100. A
validation is made when the plugin processes all the declarations, and croaks
if it's not the case.

=cut

register 'probability_route' => sub {
    my ($dsl, $probability, $method, $path, $code) = @_;

    $_routes->{$path}->{$method}->{total_score} ||= 0;
    $_routes->{$path}->{$method}->{codes} ||= [];

    $_routes->{$path}->{$method}->{total_score} += $probability;

    my $route_score = $_routes->{$path}->{$method}->{total_score};
    if ($route_score > 100) {
        croak "Probability for route [$method, '$path'] exceeds 100 ($route_score)";
    }

    push @{$_routes->{$path}->{$method}->{codes}}, [$probability, $code];
};

=method declare_probability_routes

This keyword must be called at the end of your plugin, to compile all the
pseudo-routes defined with probability_route();

It will perform sanity checks about the probability used for each routes, and
will make sure you have exactly 100 of probabilities in each method/path tuples.

=cut

register 'declare_probability_routes' => sub {
    my ($dsl) = shift;

    foreach my $path (keys %{$_routes}) {
        foreach my $method (keys %{$_routes->{$path}}) {
            my $route_score = $_routes->{$path}->{$method}->{total_score};
            if ($route_score < 100) {
                croak "Probability for route [$method, '$path'] is lower than 100 ($route_score)";
            }

            my $route_codes = $_routes->{$path}->{$method}->{codes};
            my $compiled_code = sub {
                # we need a web context to execute that, so it cannot be moved
                # out of the route's code
                my $user_score;
                if (defined $dsl->session) {
                    $user_score = oat($dsl->session->id) % 100;
                }

                my $probability_match = 0;

                foreach my $code (@{$route_codes}) {
                    my ($probability, $code) = (@$code);
                    $probability_match += $probability;

                    if ($user_score < $probability_match) {
                        return $code->();
                    }
                }
            };
            # Now we can define the real route that will host all the pseudo routes
            $dsl->$method($path, $compiled_code);
        }
    }
    # cleanup the local singleton to avoid collisions
    $_routes = {};
};

=method probability_user_score

Use this keyword to fetch the current user's score used to pick wich version
of the route are chosen. It can be handy if you wish to define your own
conditional branches.

    get '/someroute' => sub {}
        my $score = probability_user_score;
        if ($score < 50) {
            do_that();
        }
        else {
            do_this();
        }
    };

=cut

register probability_user_score => sub {
    my $dsl = shift;

    my $user_score;
    if (defined $dsl->session) {
        $user_score = oat($dsl->session->id) % 100;
    }
    return $user_score;
};

register_plugin;
1;
__END__

=head1 ACKNOWLEDGEMENTS

This module has been written during the
L<Perl Dancer 2015|https://www.perl.dance/> conference.

L<Fabrice Gabolde|https://metacpan.org/author/FGA> contributed heavily to the
design and helped me make this module so easy to write it took less than half
a day to get it into CPAN.

=pod
