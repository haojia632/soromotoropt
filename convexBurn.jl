using JuMP
using PiecewiseLinearOpt
using Gurobi
using CPLEX
using DaChoppa
using Plots

function srm_model(global_solver, nctrl, circProfile, r)
	nt = size(circProfile,1)
	regrate = 0.1
	circ = 2*pi*r # maximum circumference of the motor
	m = Model(solver = global_solver)

	# Real-space variables
	@variables m begin
	    x[1:nctrl, 1:nt]
	    absx[1:nctrl,1:nt]
	    logabsx[1:nctrl,1:nt]
	    dx[1:nctrl, 1:nt]
	    dx2[1:nctrl, 1:nt]
	    y[1:nctrl, 1:nt]
	    absy[1:nctrl,1:nt]
	    logabsy[1:nctrl,1:nt]
	    dy[1:nctrl, 1:nt]   
	    dy2[1:nctrl, 1:nt]
	    nx[1:nctrl, 1:nt]
	    ny[1:nctrl, 1:nt]
	    l[1:nctrl, 1:nt]
	    logl[1:nctrl, 1:nt]
	    l2[1:nctrl, 1:nt]
	    circ[1:nt]
	    penalty[1:nt]
	end

	# Linear constraints
	@constraints m begin
	    l[:,:] .>= 0
	    circ[:,:] .>= 0
	    # Motion of flame front 
	    x[1:nctrl-1,2:nt] .== x[1:nctrl-1,1:nt-1] + 
	            0.5*nx[1:nctrl-1,1:nt-1]*regrate + 
	            0.5*nx[2:nctrl,1:nt-1]*regrate 
	    
	    x[nctrl,2:nt] .== x[nctrl,1:nt-1] + 
	            0.5*nx[nctrl,1:nt-1]*regrate + 
	            0.5*nx[1,1:nt-1]*regrate
	    
	    y[1:nctrl-1,2:nt] .== y[1:nctrl-1,1:nt-1] + 
	            0.5*ny[1:nctrl-1,1:nt-1]*regrate + 
	            0.5*ny[2:nctrl,1:nt-1]*regrate 
	    
	    y[nctrl,2:nt] .== y[nctrl,1:nt-1] + 
	            0.5*ny[nctrl,1:nt-1]*regrate + 
	            0.5*ny[1,1:nt-1]*regrate
	    
	    dx[2:nctrl,1:nt] .== x[2:nctrl,1:nt] - x[1:nctrl-1,1:nt]
	    dx[1,1:nt] .== x[1,1:nt] - x[nctrl,1:nt]
	    dy[2:nctrl,1:nt] .== y[2:nctrl,1:nt] - y[1:nctrl-1,1:nt]
	    dy[1,1:nt] .== y[1,1:nt] - y[nctrl,1:nt]
	    l2[1:nctrl,1:nt] .== dx2[1:nctrl,1:nt] + dy2[1:nctrl,1:nt]
	    absx[1:nctrl,1:nt] .>= x[1:nctrl,1:nt]
	    absx[1:nctrl,1:nt] .>= -1*x[1:nctrl,1:nt]
	    absy[1:nctrl,1:nt] .>= y[1:nctrl,1:nt]  
	    absy[1:nctrl,1:nt] .>= -1*y[1:nctrl,1:nt]
	    nx[1:nctrl,1:nt] .== -1*dy[1:nctrl,1:nt]
	    ny[1:nctrl,1:nt] .== dx[1:nctrl,1:nt]
	end

	for i in 1:nt
	    @constraint(m, circ[i] == sum(l[1:nctrl,i]))
	    @constraint(m, penalty[i] >= circ[i] - circProfile[i])
	    @constraint(m, penalty[i] >= -(circ[i] - circProfile[i]))
	end

	# Piecewise linearization
	rvec = logspace(0.00001,2*r,10)
	for i in 1:nctrl
	    for j in 1:nt
	    @constraint(m, logabsx[i,j] == piecewiselinear(m, absx[i,j], rvec, log.(rvec)))
	    @constraint(m, logabsy[i,j] == piecewiselinear(m, absy[i,j], rvec, log.(rvec)))
	    @constraint(m, logl[i,j] == piecewiselinear(m, l[i,j], rvec, log.(rvec)))
	    end
	end

	# Purely convex (GP) constraints
	# Note: constraints commented for feasibility
	for i in 1:nctrl 
	    for j in 1:nt
	        # @NLconstraint(m, log(exp(2*logabsx[i,j]) + exp(2*logabsy[i,j])) <= 2*log(r))
	        @NLconstraint(m, exp(2*logabsx[i,j]) <= dx2[i,j])
	#         @NLconstraint(m, exp(2*logabsx[i,j]) >= dx2[i,j])
	        @NLconstraint(m, exp(2*logabsy[i,j]) <= dy2[i,j])
	#         @NLconstraint(m, exp(2*logabsy[i,j]) >= dy2[i,j])
	#         @NLconstraint(m, exp(2*logl[i,j]) >= l2[i,j])
	        @NLconstraint(m, exp(2*logl[i,j]) <= l2[i,j])
	    end
	end

	@objective(m, Min, sum(penalty))
	sol = solve(m)
	return sol
end

mip_solver = CplexSolver(CPX_PARAM_SCRIND=1, CPX_PARAM_EPINT=1e-9, 
    CPX_PARAM_EPRHS=1e-9, CPX_PARAM_EPGAP=1e-7)
# mip_solver = Gurobi.GurobiSolver(OutputFlag=1, IntFeasTol=1e-9, FeasibilityTol=1e-9, MIPGap=1e-7)
global_solver = DaChoppaSolver(log_level=1, mip_solver=mip_solver)

# Problem definition
nctrl = 8 # number of control points
nt = 6
r = 1 # radius of the motor
circProfile = pi*r*ones(nt) + 1/2*pi*linspace(0,1,nt)*r
regrate = 0.25

sol = srm_model(global_solver, nctrl, circProfile, r)