clear;
clc;

% Read data from the Excel file
data = xlsread('probs_4.xlsx');
% Extract columns 4 to 8 (assume these 5 columns are the required probability data)
probs_data = data(:, 4:8);

Cost_decided = zeros(48, 10);

for indi = 1:10
    % Select indices for the current run
    indices = indi:10:(470 + indi);
    
    % Get the probability data for these indices
    Probs = probs_data(indices, :);
    
    % Call the multi-scenario rolling optimization function,
    % which returns the cost record for the first day
    CostRecord1 = multiScenarioOptimization(Probs);
    
    % Store the result in the corresponding column of Cost_decided
    Cost_decided(:, indi) = CostRecord1;
end

% Generate a baseline probability matrix by replicating the probability vector for all 48 time steps
Probs = repmat([0.0555555555555556, 0.244444444444444, 0.400000000000000, 0.244444444444444, 0.0555555555555555], 48, 1);
Cost_distributed = multiScenarioOptimization(Probs);
TotalTime = 48;

% Calculate the mean, minimum, and maximum cost for each large time step (48×1 vectors)
MeanCost = mean(Cost_decided, 2);
MinCost  = min(Cost_decided, [], 2);
MaxCost  = max(Cost_decided, [], 2);
TimeSteps = (1:TotalTime)';  % Ensure TimeSteps is a column vector

% Plot the results
figure;
hold on;

% Construct the data for the fill area; x_fill and y_fill must have matching dimensions
x_fill = [TimeSteps; flipud(TimeSteps)];  % X-axis: from 1 to 48, then reversed
y_fill = [MinCost; flipud(MaxCost)];        % Y-axis: the minimum cost, then the reversed maximum cost

% Plot the filled area representing the cost range at each time step
fill(x_fill, y_fill, [0.8 0.4 0.8], 'FaceAlpha', 0.3, 'EdgeColor', 'none');

% Plot the mean cost curve (3rd Quantile Cost) and the baseline cost curve (Original Prob)
plot(TimeSteps, MeanCost, 'b-', 'LineWidth', 2, 'DisplayName', '3rd Quantile Cost');
plot(TimeSteps, Cost_distributed, 'r-', 'LineWidth', 2, 'DisplayName', 'Original Prob');

% Add axis labels, title, and legend
xlabel('Large Time Step');
ylabel('Cost');
title('Cost Analysis: 3rd Quantile Cost');
legend('Location', 'Best');
grid on;
hold off;

% Save the cost results to .mat files
save('Costs_Dist.mat', "Cost_distributed");
save('Cost_Tests.mat', "Cost_decided");
