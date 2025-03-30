function CostRecord1 = multiScenarioOptimization(Probs)
% multiScenarioOptimization: Multi-scenario, multi-stage rolling optimization
%
% Input:
%   Probs - A matrix used to replace the original probability data 
%           (each large time step's probabilities)
%
% Output:
%   CostRecord1 - Cost records for the first day (the first 48 large time steps)
%
% Example:
%   Probs = csvread('probs.csv');
%   CostRecord1 = multiScenarioOptimization(Probs);

%% ========== 1. Data Reading & Initialization ==========
Dataset       = xlsread('WindandLoad.xlsx');
Demandset     = Dataset(49:100,1);      % Demand data (example: scaled units)
WindForecast  = Dataset(49:100,3);
Windreal      = Dataset(49:100,2);

load('ScenarioTree.mat');  
% ScenarioTree.mat contains:
%   - time_steps: Each rolling optimization looks 4 hours ahead (e.g., time_steps = 4)
%   - quantiles_flip, wind_error, prob, etc.
%     where length(quantiles_flip) indicates the number of scenarios

% Basic parameters
VOLL           = 3e5;      % Value of Lost Load (e.g., 150000 per hour)
Wind_capacity  = 200;      % Maximum wind capacity (MW)
num_gen        = 3;        % Number of thermal generators
tau            = 1;        % 1-hour time step
TotalTime      = 48;       % Number of large time steps for rolling optimization

% Generator costs and startup costs
c   = [20e3; 30e3; 60e3];
stc = [2e6; 1e6; 2e6];

% Generator output limits
Gen_limits = [3 10;  % G1
              2 12;  % G2
              0 15]; % G3

% Ramp rate limits
Ramp_limits = [2 2;
               2 2;
               3 3];

% Initial generator commitment state
Initial_commitment = [1; 1; 0];

%% ========== 4. Initialize Variables to Store Final Results ==========
GenOutput      = zeros(TotalTime, num_gen);
DemandRecord   = zeros(TotalTime, 1);
WindRecord     = zeros(TotalTime, 1);
LoadCurtRecord = zeros(TotalTime, 1);
WindCurtRecord = zeros(TotalTime, 1);
CostRecord     = zeros(TotalTime, 1);

%% ========== 5. Main Loop (Rolling Optimization) ==========
for time = 1:TotalTime
    disp(['Current large time step: ', num2str(time)]);
    
    %% 5.1 Read the demand and wind data for the next 4 hours (k = 1..4)
    Demand_4h = Demandset(time:time+3);
    
    % Update the probabilities based on the input Probs (here only replacing part of each large time step)
    for nprob = 1:5
        prob(nprob,2:4) = Probs(time, nprob);
    end
    
    % Use actual wind for the first hour and forecast wind for the next 3 hours
    WindForecast_4h = [Windreal(time), WindForecast(time+1:time+3)'];
    
    % Construct the wind scenario tree: Wind_tree(n,k)
    Wind_tree = zeros(length(quantiles_flip), time_steps);
    for k = 1:time_steps
        base_wind = WindForecast_4h(k);
        for n = 1:length(quantiles_flip)
            Wind_tree(n,k) = base_wind * (1 + wind_error(n,k));
            if Wind_tree(n,k) > Wind_capacity
                Wind_tree(n,k) = Wind_capacity;
            end
        end
    end
    
    %% 5.2 Define Decision Variables
    % (a) Generator decision variables: output (x), commitment (y), startup (su)
    x   = cell(length(quantiles_flip), time_steps);
    y   = cell(length(quantiles_flip), time_steps);
    su  = cell(length(quantiles_flip), time_steps);
    
    % (b) Load and wind curtailment variables
    Load_curtailed = sdpvar(length(quantiles_flip), time_steps, 'full');
    Wind_curtailed = sdpvar(length(quantiles_flip), time_steps, 'full');
    
    % (c) Node cost variable
    Cost_node = sdpvar(length(quantiles_flip), time_steps, 'full');
    
    %% 5.3 Construct Constraints
    Constraints = [];
    for n = 1:length(quantiles_flip)
        for k = 1:time_steps
            % Define decision variables for each generator
            x{n,k}  = sdpvar(num_gen,1);
            y{n,k}  = binvar(num_gen,1);
            su{n,k} = sdpvar(num_gen,1);
            
            % Initial commitment state (applied only for the first hour of the first large time step)
            if (time == 1) && (k == 1)
                Constraints = [Constraints, y{n,k} == Initial_commitment];
            end
            
            % Startup: For k = 1, set su equal to y; for k >= 2, enforce su >= y(k) - y(k-1) and su >= 0
            if k == 1
                Constraints = [Constraints, su{n,k} == y{n,k}];
            else
                Constraints = [Constraints, su{n,k} >= y{n,k} - y{n,k-1}, su{n,k} >= 0];
            end
            
            % Generator output limits
            for i = 1:num_gen
                Constraints = [Constraints, y{n,k}(i)*Gen_limits(i,1) <= x{n,k}(i) <= y{n,k}(i)*Gen_limits(i,2)];
            end
            
            % Ramp rate constraints (between consecutive hours)
            if k >= 2
                for i = 1:num_gen
                    Constraints = [Constraints, -tau*Ramp_limits(i,1)*y{n,k-1}(i) <= (x{n,k}(i) - x{n,k-1}(i)) <= tau*Ramp_limits(i,2)*y{n,k-1}(i)];
                end
            end
            
            % Power balance: Generation + Wind - Wind Curtailment = Demand - Load Curtailment
            Constraints = [Constraints, sum(x{n,k}) + Wind_tree(n,k) - Wind_curtailed(n,k) == Demand_4h(k) - Load_curtailed(n,k)];
            
            % Bounds for curtailment variables
            Constraints = [Constraints, 0 <= Wind_curtailed(n,k) <= Wind_tree(n,k), ...
                                          0 <= Load_curtailed(n,k) <= Demand_4h(k)];
            
            % Node cost function: startup cost + generation cost and load curtailment penalty
            Cost_node(n,k) = stc' * su{n,k} + tau*( c' * x{n,k} + VOLL * Load_curtailed(n,k) );
        end
    end
    
    %% 5.4 Define Objective Function (weighted sum of costs across all scenarios and time periods)
    Objective = sum(sum(prob .* Cost_node));
    
    %% 5.5 Solve the Optimization Problem
    options = sdpsettings('solver','gurobi','verbose',0);
    sol = optimize(Constraints, Objective, options);
    if sol.problem ~= 0
        warning('Solver did not return a normal status. Info: %s', sol.info);
    end
    
    %% 5.6 Extract the expected values for the first hour and record the results
    x1_gen_exp    = value(x{3,1});
    loadcurt1_exp = value(Load_curtailed(3,1));
    windcurt1_exp = value(Wind_curtailed(3,1));
    
    GenOutput(time,:)    = x1_gen_exp';
    DemandRecord(time)   = Demandset(time);
    WindRecord(time)     = Windreal(time);
    LoadCurtRecord(time) = loadcurt1_exp;
    WindCurtRecord(time) = windcurt1_exp;
    CostRecord(time)     = value(Cost_node(3,1));
end

%% ========== 7. Post Processing and Output First Day Statistics ==========
CostRecord1     = CostRecord(1:48);          % Cost records for the first day
WindCurtRecord1 = WindCurtRecord(1:48)/2;      % First day wind curtailment (adjusted units)
LoadCurtRecord1 = LoadCurtRecord(1:48)/2;      % First day load curtailment (adjusted units)

TotalCost1     = sum(CostRecord1);
TotalWindCurt1 = sum(WindCurtRecord1);
TotalLoadCurt1 = sum(LoadCurtRecord1);

disp('-----------------------------------------');
disp('First Day Statistics:');
disp(['Total Cost (Day 1)         = ', num2str(TotalCost1)]);
disp(['Total Wind Curtailment (Day 1) = ', num2str(TotalWindCurt1), ' (GW·h)']);
disp(['Total Load Curtailment (Day 1) = ', num2str(TotalLoadCurt1), ' (GW·h)']);
disp('-----------------------------------------');
end
