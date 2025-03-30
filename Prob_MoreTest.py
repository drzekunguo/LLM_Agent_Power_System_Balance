import os
from autogen import ConversableAgent
import json
import pandas as pd
import LLMAzAPI
import csv
import numpy as np

os.environ['AUTOGEN_DISABLE_CACHE'] = 'True'

llm_config_GPT4 = {
    "config_list": [
        {
            "api_key": os.environ['OPENAI_API_KEY'],
            "api_type": "openai",
            "base_url": os.environ['OPENAI_ENDPOINT'],
        }
    ]
}

SysPrompt = """I am currently constructing a wind power scenario tree based on an AR(1) process. Below is part of the MATLAB code I am using. Please read and understand it first:
%% Parameters and Initialization
quantiles = [0.01 0.1 0.5 0.9 0.99];
time_steps = 4;

mu = 0;
sigma = 1;

phi = 1.2;
eps_C = 0.14;

%% Flip the quantiles vector
quantiles_flip = flip(quantiles);

% Construct wind_error
wind_error(1:length(quantiles_flip),1) = zeros(length(quantiles_flip),1);
for k=2:time_steps
    for n=1:length(quantiles_flip)
        if k==2
            wind_error(n,k) = phi * wind_error(n,k-1) + eps_C * norminv(quantiles_flip(n), mu, sigma);
        else
            wind_error(n,k) = phi * wind_error(n,k-1);
        end
    end
end

% Initialize the probability matrix
prob(1:length(quantiles),1) = zeros(length(quantiles),1);
prob(ceil(length(quantiles)/2),1) = 1;  % The middle node probability is set to 1 for the root node

% Branching at the 1st layer (k=2)
for k=2
    for n=1:length(quantiles)
        if n==1
            prob(n,k) = 0.5 * (quantiles(2)^2 / (quantiles(2) - quantiles(1)));
        elseif n==2
            prob(n,k) = 0.5 * ( quantiles(3) - quantiles(1) ...
                              - quantiles(1)^2 / (quantiles(2) - quantiles(1)) );
        elseif (n>2) && (n<length(quantiles)-1)
            prob(n,k) = 0.5 * ( quantiles(n+1) - quantiles(n-1) );
        elseif n==length(quantiles)-1
            prob(n,k) = 0.5 * ( quantiles(end) - quantiles(end-2) ...
                              - (1 - quantiles(end))^2 / (quantiles(end) - quantiles(end-1)) );
        else
            prob(n,k) = 0.5 * ( (1 - quantiles(end-1))^2 / (quantiles(end) - quantiles(end-1)) );
        end
    end
end

% The probability distribution for subsequent time steps (k=3..4) is the same as at step 2
for k=3:time_steps
    prob(:,k) = prob(:,2);
end

% The resulting five branch probabilities (for step 2 and onward) are:
% [0.0555555555555556, 0.244444444444444, 0.4, 0.244444444444444, 0.0555555555555555]

You have been provided with two sets of data: one is the actual power demand, and the other is the forecasted power demand. You will make some judgments and outputs based on these two sets of values.

Now, while keeping the same quantiles (i.e., [0.01, 0.1, 0.5, 0.9, 0.99]), I want you to give me a new branching probability vector, prob_new, that meets the following requirements or objectives (please think carefully):
You are tasked with analyzing historical forecast error data and adjusting probability distributions accordingly. To do so, you must first compute the error values and derive key statistical parameters such as mean and standard deviation.

Example Calculation:
The following example illustrates how to compute forecast errors and derive their statistical properties:
Step 1: Compute the errors
For each pair of actual and forecasted values, calculate the error as:
e(t) = Actual(t) - Forecasted(t)
Step 2: Compute the mean and standard deviation of the errors
Use the following formulas to derive the mean (μ) and standard deviation (σ) of the error distribution:
μ = (∑ e(t)) / N
σ = √((∑ (e(t) - μ)²) / (N - 1))
These statistical parameters will help in defining quantile-based scenario generation. Proceed by adjusting the probability vector accordingly based on observed error patterns.


Still have 5 branches, corresponding to the same quantiles [0.01, 0.1, 0.5, 0.9, 0.99].
The sum of the entries in prob_new must be 1.
prob_new should be different from the original [0.05556, 0.24444, 0.4, 0.24444, 0.05556], adjusted according to past forecast errors. Note that this distribution does not have to be symmetric in the middle—it can be biased upwards or downwards. Please provide a rationale.
Ideally, briefly explain why your new branching probability might be more reasonable for wind power forecasting or how it would affect results.
If necessary, you can introduce a revised formula or approach (it could be heuristic or a strict mathematical derivation), but there is no need to provide the full MATLAB code.
Your response should include:

A new probability vector prob_new (5 values, each ≥ 0 and summing to 1),
And an explanation of how you arrived at this new distribution.
In your answer, do not completely discard or ignore my original code structure. Rather, refer to its logic and the position of the quantiles; however, feel free to propose your own strategy for allocating the probabilities. Thank you!

That is my requirement. Please directly base your response on this information, give me a new prob_new vector, and explain your reasoning.
 ###"""

# Create GPT-4 agent
GPT4 = ConversableAgent(
    "GPT4",
    system_message=SysPrompt,
    llm_config=llm_config_GPT4,
    human_input_mode="NEVER"
)

# Create Scraper agent to extract 'prob_new'
Scraper = ConversableAgent(
    "Scraper",
    system_message="""
You are a scraper. You need to extract 'the prob_new finally selected' from the given text. The final output should be like this,put 5 probs in it:
{
  "prob_new": []
}
""",
    llm_config=llm_config_GPT4,
    human_input_mode="NEVER",
)

# Create User agent
User = ConversableAgent(
    "User",
    system_message="You are providing Electrical Information",
    llm_config=None,
    human_input_mode="NEVER",
)

# Read the Excel file 'WindandLoad.xlsx' and select the last two columns
df = pd.read_excel('WindandLoad.xlsx', header=None)
# Select the last two columns (assume the file has at least two columns)
df = df.iloc[:, -2:]

row_num = 20

# List to store all inference results
all_results = []

# Set starting index and time step counter
start_index = 28
time_step = 0

# We use only one model: GPT4
model_name = "GPT4"

while start_index + row_num <= 100:
    # Extract subset of data (past 20 time steps)
    subset = df.iloc[start_index:start_index + row_num]
    # Construct input message
    message = "The forecast and actual values for the past 20 time steps are:\n"
    for _, row in subset.iterrows():
        message += f"{row[0]}  {row[1]}\n"
    
    # Run inference 10 times per time step
    for run in range(1, 11):
        result_llm = User.initiate_chat(GPT4, message=message, max_turns=1)
        result_scraper = User.initiate_chat(Scraper, message=result_llm.chat_history[1]['content'], max_turns=1)
        try:
            parsed_result = json.loads(result_scraper.chat_history[1]['content'])
        except Exception as e:
            try:
                # Try trimming extra characters if needed
                parsed_result = json.loads(result_scraper.chat_history[1]['content'][8:-4])
            except Exception as e2:
                # As a fallback, try one more time
                result_llm = User.initiate_chat(GPT4, message=message, max_turns=1)
                result_scraper = User.initiate_chat(Scraper, message=result_llm.chat_history[1]['content'], max_turns=1)
                parsed_result = json.loads(result_scraper.chat_history[1]['content'])
        
        result_entry = {
            "time_step": time_step,
            "model": model_name,
            "run": run,
            "prob_new": parsed_result.get("prob_new")
        }
        all_results.append(result_entry)
    
    start_index += 1
    time_step += 1

# Convert all results to DataFrame
df_results = pd.DataFrame(all_results)
# Expand the 'prob_new' list into 5 separate columns
prob_df = pd.DataFrame(df_results['prob_new'].tolist(), index=df_results.index)
prob_df.columns = ["prob_new_1", "prob_new_2", "prob_new_3", "prob_new_4", "prob_new_5"]
df_results = df_results.drop(columns=["prob_new"]).join(prob_df)

# Save the results to an Excel file with model name suffix
excel_file = f"probs_{model_name}.xlsx"
df_results.to_excel(excel_file, index=False)
print(f"Data for model {model_name} has been saved to {excel_file}.")