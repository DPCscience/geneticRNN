% hebbRNN_Example_DNMS
%
% This function illustrates an example of reward-modulated Hebbian learning
% in a recurrent neural network to complete a delayed nonmatch-to-sample
% task.
%
%
% Copyright (c) Jonathan A Michaels 2016
% German Primate Center
% jonathanamichaels AT gmail DOT com
%
% If used in published work please see repository README.md for citation
% and license information: https://github.com/JonathanAMichaels/hebbRNN


clear
close all

%% Generate inputs and outputs
inp = cell(1,4);
targ = cell(1,4);
level = 1;
cue1Time = 1:20;
cue2Time = 41:60;
totalTime = 100;
checkTime = 81:100;
target1 = 1;
target2 = -1;
for type = 1:4
    inp{type} = zeros(2, totalTime);
    if type == 1
        inp{type}(1, [cue1Time cue2Time]) = level;
        targ{type} = [nan(1, checkTime(1)-1) ones(1, totalTime-checkTime(1)+1)]*target1;
    elseif type == 2
        inp{type}(2, [cue1Time cue2Time]) = level;
        targ{type} = [nan(1, checkTime(1)-1) ones(1, totalTime-checkTime(1)+1)]*target1;
    elseif type == 3
        inp{type}(1, cue1Time) = level;
        inp{type}(2, cue2Time) = level;
        targ{type} = [nan(1, checkTime(1)-1) ones(1, totalTime-checkTime(1)+1)]*target2;
    elseif type == 4
        inp{type}(2, cue1Time) = level;
        inp{type}(1, cue2Time) = level;
        targ{type} = [nan(1, checkTime(1)-1) ones(1, totalTime-checkTime(1)+1)]*target2;
    end
end
% In the delayed nonmatch-to-sample task the network receives two temporally
% separated inputs. Each input lasts 200ms and there is a 200ms gap between them.
% The goal of the task is to respond with one value if the inputs were
% identical, and a different value if they were not. This response must be
% independent of the order of the signals and therefore requires the
% network to remember the first input!

%% Initialize network parameters
N = 100; % Number of neurons
B = size(targ{1},1); % Outputs
I = size(inp{1},1); % Inputs
p = 1; % Sparsity
g = 1.2; % Spectral scaling
dt = 1; % Time step
tau = 10; % Time constant

%% Initialize learning parameters
evalOpts = [2 1]; % Plotting level and frequency of evaluation

policyInitInputs = {N, B, I, p, g, dt, tau};
policyInitInputsOptional = {'feedback', true, 'actFun', 'tanh'};

mutationPower = 5e-2;
populationSize = 2000;
truncationSize = 100;
fitnessFunInputs = targ;
policyInitFun = @geneticRNN_create_model;

%% Train network
% This step should take about 5 minutes, depending on your processor.
% Can be stopped at any time by pressing the STOP button.
% Look inside to see information about the many optional parameters.
[net, learnStats] = geneticRNN_learn_model_2(mutationPower, populationSize, truncationSize, fitnessFunInputs, policyInitInputs, ...
    'input', inp, ...
    'evalOpts', evalOpts, ...
    'policyInitInputsOptional', policyInitInputsOptional);

%% Run network
[Z0, Z1, R, dR, X, kin] = geneticRNN_run_model(net(1), 'input', inp);

