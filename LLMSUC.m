% =============================
%   Multi-scenario, multi-stage (no storage version)
%   (Rolling + Scenario Tree)
% =============================
clearvars
clc

%% ========== 1. Data Reading & Initialization ==========

Dataset       = xlsread('WindandLoad.xlsx');
Probs         = csvread('probs.csv');
Demandset     = Dataset(49:100,1);      % (example) scaled units
WindForecast  = Dataset(49:100,3);  
Windreal      = Dataset(49:100,2);

load('ScenarioTree.mat');  
% The data includes:
%   - time_steps = 4 (we look 4 hours ahead each time)
%   - quantiles_flip, wind_error, prob (scenario probabilities, etc.)
%   where length(quantiles_flip) = number of scenarios = N

% Basic parameters
VOLL           = 3e5;  %150000 per hour
Wind_capacity  = 200;
num_gen        = 3;    % number of thermal generators
tau            = 1;    % 1-hour time step
TotalTime      = 48;   % number of rolling-optimization steps (large time steps)

% Generator costs & startup costs
c   = [10e3; 15e3; 30e3];
stc = [1e6; 5e5; 1e6];

% Generator output limits
Gen_limits = [3 10;  % G1
              2 12;  % G2
              0 15]; % G3

% Ramp up/down limits
Ramp_limits = [4 4;
               4 4;
               6 6];

% Initial commitment state
Initial_commitment = [1; 1; 0];

%% ========== 2. (Storage parameters & salvage value) -- Removed ==========

% -- Original storage-related code was removed --

%% ========== 3. (Salvage Value) -- Removed ==========

% -- Original salvage_value, E0, etc. were removed --

%% ========== 4. Variables to store final results at each large time step ==========

GenOutput      = zeros(TotalTime, num_gen);  
DemandRecord   = zeros(TotalTime, 1);        
WindRecord     = zeros(TotalTime, 1);        
LoadCurtRecord = zeros(TotalTime, 1);        
WindCurtRecord = zeros(TotalTime, 1);        
CostRecord     = zeros(TotalTime, 1);

% -- Original ESS_Charge / ESS_Discharge / ESS_SoC (storage) variables were removed --

%% ========== 5. Main Loop (Rolling Optimization) ==========

for time = 1:TotalTime
    time
    %% 5.1 Read the demand & wind for the next 4 hours (k=1..4)
    Demand_4h       = Demandset(time : time+3);
    
    for nprob = 1:5
        prob(nprob,2:4) = Probs(time,nprob);
    end
    
    % Use real wind data for the first hour, forecast data for the next 3 hours
    WindForecast_4h = [Windreal(time), WindForecast(time+1:time+3)'];
    
    % Build the wind scenario tree: Wind_tree(n,k)
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
    
    %% 5.2 Define decision variables
    
    % (a) Generator decisions
    x   = cell(length(quantiles_flip), time_steps);  % Generator outputs (MW)
    y   = cell(length(quantiles_flip), time_steps);  % Commitment state (0/1)
    su  = cell(length(quantiles_flip), time_steps);  % Startup amount (continuous)
    
    % (b) Load & wind curtailment
    Load_curtailed = sdpvar(length(quantiles_flip), time_steps, 'full');
    Wind_curtailed = sdpvar(length(quantiles_flip), time_steps, 'full');
    
    % (c) Cost matrix
    Cost_node = sdpvar(length(quantiles_flip), time_steps, 'full');
    
    %% 5.3 Construct constraints
    Constraints = [];
    for n = 1:length(quantiles_flip)
        for k = 1:time_steps
            
            % ---------- Generator-related ----------
            x{n,k}  = sdpvar(num_gen,1);
            y{n,k}  = binvar(num_gen,1);
            su{n,k} = sdpvar(num_gen,1);
            
            % Initial commitment state (only applies in the first step and k=1)
            if (time == 1) && (k == 1)
                Constraints = [Constraints, y{n,k} == Initial_commitment];
            end
            
            % Startup amount: su >= y(k) - y(k-1)
            if k == 1
                Constraints = [Constraints, su{n,k} == y{n,k}];
            else
                Constraints = [Constraints, ...
                    su{n,k} >= y{n,k} - y{n,k-1}, ...
                    su{n,k} >= 0];
            end
            
            % Generator output limits
            for i = 1:num_gen
                Constraints = [Constraints, ...
                    y{n,k}(i)*Gen_limits(i,1) <= x{n,k}(i) <= y{n,k}(i)*Gen_limits(i,2)];
            end
            
            % Ramp constraints
            if k >= 2
                for i = 1:num_gen
                    Constraints = [Constraints, ...
                        -tau*Ramp_limits(i,1)*y{n,k-1}(i) <= (x{n,k}(i) - x{n,k-1}(i)) ...
                                                            <= tau*Ramp_limits(i,2)*y{n,k-1}(i)];
                end
            end
            
            % ---------- Power balance: Gen + Wind - WindCurt = Demand - LoadCurt ----------
            Constraints = [Constraints, ...
                sum(x{n,k}) + Wind_tree(n,k) - Wind_curtailed(n,k) ...
                == Demand_4h(k) - Load_curtailed(n,k)];
            
            % ---------- Load & wind curtailment limits ----------
            Constraints = [Constraints, ...
                0 <= Wind_curtailed(n,k) <= Wind_tree(n,k), ...
                0 <= Load_curtailed(n,k) <= Demand_4h(k)];
            
            % ---------- Cost function (node n, period k) ----------
            Cost_node(n,k) = stc' * su{n,k} ...
                             + tau * ( c' * x{n,k} + VOLL * Load_curtailed(n,k));
        end
    end
    
    %% 5.4 Objective Function (no storage, only generation + load + wind curtailment costs)
    % sum_{n,k} [prob(n) * Cost_node(n,k)]
    Objective = sum(sum(prob .* Cost_node));
    
    %% 5.5 Solve
    options = sdpsettings('solver','gurobi','verbose',0);
    sol = optimize(Constraints, Objective, options);
    if sol.problem ~= 0
        warning('Solver did not return status 0. Info: %s', sol.info);
    end
    
    %% 5.6 Extract the expected value for the first hour (k=1) & record
    % Expected generator output, load curtailment, wind curtailment
    x1_gen_exp    = value(x{3,1});
    loadcurt1_exp = value(Load_curtailed(3,1));
    windcurt1_exp = value(Wind_curtailed(3,1));
    
    % Store the results (first hour)
    GenOutput(time,:)    = x1_gen_exp';
    DemandRecord(time)   = Demandset(time);
    WindRecord(time)     = Windreal(time);
    LoadCurtRecord(time) = loadcurt1_exp;
    WindCurtRecord(time) = windcurt1_exp;
    CostRecord(time)     = value(Cost_node(3,1));
    
    %% 5.7 No storage, so no SoC update (removed)
    % -- Original logic for E0 update was removed --
end

%% ========== 6. Post-processing & plotting ==========

% (a) Actual injected wind
ActualWindUsed = WindRecord - WindCurtRecord;
ActualWindUsed(ActualWindUsed < 0) = 0;

% (b) Stacked plot: generator output + wind vs. demand
CombinedOutput = [GenOutput, ActualWindUsed];
figure('Name','Generator output + wind (stacked) and demand','Color','w');
bar(1:TotalTime, CombinedOutput, 'stacked'); hold on;
plot(1:TotalTime, DemandRecord, '-ok', 'LineWidth',2,'MarkerFaceColor','r');
xlabel('Large time step (time)');
ylabel('Power (GW)');
legend({'Gen1','Gen2','Gen3','Wind','Demand'}, 'Location','Best');
title('Generator + Wind Stacked, with Demand Curve');
grid on;

% (c) Load & wind curtailment
figure('Name','Load Curtail & Wind Curtail','Color','w');
plot(1:TotalTime, LoadCurtRecord, '-or','LineWidth',2,'MarkerFaceColor','r'); hold on;
plot(1:TotalTime, WindCurtRecord, '-*b','LineWidth',2,'MarkerFaceColor','b');
xlabel('Large time step (time)');
ylabel('Curtailment (GW)');
legend({'Load Curtail','Wind Curtail'}, 'Location','Best');
title('Load Curtailment & Wind Curtailment');
grid on;


%% ========== 7. Compute and output total costs, wind, and load curtailment for two days ==========

% Assume the input data has a length of 96 records
% The first 48 are Day 1, 49~96 are Day 2

% Split data
CostRecord1     = CostRecord(1:48);          % Day 1 cost records
WindCurtRecord1 = WindCurtRecord(1:48)/2;    % Day 1 wind curtailment
LoadCurtRecord1 = LoadCurtRecord(1:48)/2;    % Day 1 load curtailment

% Day 1 calculations
TotalCost1     = sum(CostRecord1);      
TotalWindCurt1 = sum(WindCurtRecord1); 
TotalLoadCurt1 = sum(LoadCurtRecord1); 

% Output results
disp('-----------------------------------------');
disp('Day 1 Statistics:');
disp(['Total cost (Day 1)         = ', num2str(TotalCost1)]);
disp(['Total wind curtail (Day 1) = ', num2str(TotalWindCurt1), ' (GW·h)']);
disp(['Total load curtail (Day 1) = ', num2str(TotalLoadCurt1), ' (GW·h)']);
disp('-----------------------------------------');
