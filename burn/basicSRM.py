from gpkit import Variable, Model, parse_variables, units
from gpkit import SignomialsEnabled, SignomialEquality, Vectorize

from relaxed_constants import relaxed_constants, post_process


class Section(Model):
    """ basic SRM section model

    Variables
    -------------
    Aratio                            [-]          area ratio
    A_in                              [m^2]        area in
    A_out                             [m^2]        area out
    A_avg                             [m^2]        average area
    A_b                               [m^2]        burn area
    l_b                               [m]          avg burn length
    l                                 [m]          section length
    mdot_in                           [kg/s]       mass flow rate in
    mdot_out                          [kg/s]       mass flow rate out
    rho_in                            [kg/m^3]   density in
    rho_out                           [kg/m^3]   density out
    P_t_in                            [Pa]         stagnation pressure in
    P_t_out                           [Pa]         stagnation pressure out
    P_in                              [Pa]         static pressure at inlet
    P_out                             [Pa]         static pressure at outlet
    P_chamb                           [Pa]         chamber static pressure
    V_chamb                           [m^3]        chamber volume
    V_fuel                            [m^3]        fuel volume
    T_t_in                            [K]          stagnation temperature in
    T_t_out                           [K]          stagnation temperature out
    u_in                              [m/s]        velocity in
    u_out                             [m/s]        velocity out
    u_avg                             [m/s]        average velocity
    r                                 [mm/s]       burn rate
    q                                 [kg/s]       rate of generation of products
    T_amb                273          [K]          ambient temperature
    r_c                  5.606        [mm/s]        burn rate coefficient
    r_k                  0.05         [1/(m/s)]    erosive burn rate coefficient
    rho_p                1700         [kg/m^3]     propellant density
    k_comb_p             1.23e6       [J/kg]       propellant specific heat of combustion
    c_p                  1000         [J/kg/K]     specific heat of combustion products
    """

    def setup(self):
        exec parse_variables(Section.__doc__)
        constraints = [
            # Taking averages,
            u_in*u_out == u_avg**2,
            A_in*A_out == A_avg**2,
            # Volume of chamber
            V_chamb == A_avg*l,
            # Area ratio
            A_in / A_out == Aratio,
            # Mass flow rate
            rho_in * u_in * A_in == mdot_in,
            rho_out * u_out * A_out == mdot_out,
            # Burn rate (Saint-Robert's Law, coefficients taken for Space Shuttle SRM)
            # Note: erosive burning neglected for now
            r == r_c * (P_chamb/1e6*units('1/Pa')) ** 0.35,  # *(1 + r_k*u_avg),
            # Product generation rate
            q == rho_p * A_b * r,
            A_b == l_b * l,
            # Stagnation quantities
            P_t_out >= P_out + 0.5*rho_out*u_out**2,
            P_t_in >= P_in + 0.5*rho_in*u_in**2,
        ]
        with SignomialsEnabled():
            constraints += [
                # Mass flows
                mdot_in + q >= mdot_out,
                # Temperatures
                T_t_out*mdot_out <= mdot_in*T_t_in + q*T_amb + q*k_comb_p/c_p,
            ]
        return constraints

def test_section():
    m = Section()
    m.substitutions.update({
        m.P_t_in        :1000*units('kPa'),
        m.l             :1*units('cm'),
        m.T_t_in        :700*units('K'),
        mdot_in         :1*units('kg/s'),
        A_in            :10*units('cm^2'),
        u_in            :10*units('m/s'),
    })
    m.cost = m.u_out*m.P_t_out


if __name__ == "__main__":
    pass
