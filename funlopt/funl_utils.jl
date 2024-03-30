
include("../trajopt/dynamics.jl")
include("../trajopt/discretize.jl")
include("funl_dynamics.jl")
using LinearAlgebra

function get_radius_angle_Ellipse2D(Q_list)
    radius_list = []
    angle_list = []

    for i in 1:size(Q_list,3)
        Q_ = Q_list[:,:,i]
        eigval = eigvals(inv(Q_))
        radius = sqrt.(1 ./ eigval)
        # println("radius of x,y,theta: ", radius)
        A = [1 0 0; 0 1 0]
        Q_proj = A * Q_ * A'
        Q_inv = inv(Q_proj)
        eigval, eigvec = eigen(Q_inv)
        radius = sqrt.(1 ./ eigval)
        # println("radius of x and y: ", radius)
        rnew = eigvec * [radius[1]; 0]
        angle = atan(rnew[2], rnew[1])
        push!(radius_list, radius)
        push!(angle_list, angle)
    end
    return radius_list, angle_list
end

function propagate_multiple_FOH(model::FunnelDynamics,dynamics::Dynamics,
    x::Matrix,u::Matrix,T::Vector,
    Q::Array{Float64,3},Y::Array{Float64,3},Z::Array{Float64,3})
    N = size(x,2) - 1
    ix = model.ix
    iu = model.iu
    iq = model.iq
    iy = model.iy

    idx_x = 1:ix
    idx_q = (ix+1):(ix+iq)

    function dvdt(out,V,p,t)
        um = p[1]
        up = p[2]
        ym = p[3]
        yp = p[4]
        zm = p[5]
        zp = p[6]
        dt = p[7]

        alpha = (dt - t) / dt
        beta = t / dt

        u_ = alpha * um + beta * up
        y_ = alpha * ym + beta * yp
        z_ = alpha * zm + beta * zp

        x_ = V[idx_x]
        q_ = V[idx_q]

        # traj terms
        f = forward(dynamics,x_,u_)
        A,B = diff(dynamics,x_,u_)
        # funl terms
        F = forward(model,q_,y_,z_,A,B)

        dxdt = f
        dqdt = F
        dV = [dxdt;dqdt]
        out .= dV[:]
    end

    tprop = []
    xprop = []
    uprop = []
    qprop = []
    yprop = []
    Qfwd = zeros(size(Q))
    Qfwd[:,:,1] = Q[:,:,1]
    for i = 1:N
        V0 = [x[:,i];vec(Q[:,:,i])][:]

        um = u[:,i]
        up = u[:,i+1]
        ym = vec(Y[:,:,i])
        yp = vec(Y[:,:,i+1])
        zm = vec(Z[:,:,i])
        zp = vec(Z[:,:,i+1])
        dt = T[i]

        prob = ODEProblem(dvdt,V0,(0,dt),(um,up,ym,yp,zm,zp,dt))
        sol = solve(prob, Tsit5(), reltol=1e-6, abstol=1e-6;verbose=false);

        tode = sol.t
        uode = zeros(iu,size(tode,1))
        yode = zeros(iy,size(tode,1))
        for idx in 1:length(tode)
            alpha = (dt - tode[idx]) / dt
            beta = tode[idx] / dt
            uode[:,idx] .= alpha * um + beta * up
            yode[:,idx] .= alpha * ym + beta * yp
        end
        ode = stack(sol.u)
        xode = ode[idx_x,:]
        qode = ode[idx_q,:]
        if i == 1
            tprop = tode
            xprop = xode
            uprop = uode
            qprop = qode
            yprop = yode
        else 
            tprop = vcat(tprop,sum(T[1:i-1]).+tode)
            xprop = hcat(xprop,xode)
            uprop = hcat(uprop,uode)
            qprop = hcat(qprop,qode)
            yprop = hcat(yprop,yode)
        end
        Qfwd[:,:,i+1] = reshape(qode[:,end],(ix,ix))
    end
    Qprop = zeros(ix,ix,length(tprop))
    Yprop = zeros(iu,Int64(iy/iu),length(tprop))
    for i in 1:length(tprop)
        Qprop[:,:,i] .= reshape(qprop[:,i],(ix,ix))
        Yprop[:,:,i] .= reshape(yprop[:,i],(iu,Int64(iy/iu)))
    end
    return Qfwd,tprop,xprop,uprop,Qprop,Yprop
end


# def get_radius_angle(Q_list) :
#     radius_list = []
#     angle_list = []
#     for Q_ in Q_list :
#         eig,_ = np.linalg.eig(np.linalg.inv(Q_))
#         radius = np.sqrt(1/eig)
#         # print("radius of x,y,theta",radius)
#         A = np.array([[1,0,0],[0,1,0]])
#         # Q_proj = project_ellipse(Q_) 
#         Q_proj = A@Q_@A.T
#         Q_inv = np.linalg.inv(Q_proj)
#         eig,eig_vec = np.linalg.eig(Q_inv)
#         radius = np.sqrt(1/eig)
#         # print("radius of x and y",radius)
#         rnew = eig_vec@np.array([[radius[0]],[0]])
#         angle = np.arctan2(rnew[1],rnew[0])
#         radius_list.append(radius)
#         angle_list.append(angle)

#     return radius_list,angle_list