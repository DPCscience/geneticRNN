function [winner, varargout] = geneticRNN_learn_model(mutationPower, populationSize, truncationSize, fitnessFunInputs, policyInitInputs, varargin)

% net = hebbRNN_learn_model(x0, net, F, perturbProb, eta, varargin)
%
% This function trains a recurrent neural network using reward-modulated
% Hebbian learning to produce desired outputs. During each trial the
% activations of random neurons are randomly perturbed. All fluctuations in
% the activation of each neuron are accumulated (supra-linearly) as an
% elegibility trace. At the end of each trial the error of the output is
% compared against the expected error and the difference is used to
% reinforce connectivity changes (net.J) that produce the desired output.
%
% The details of training the network are based on those
% presented in the following work:
% "Flexible decision-making in recurrent neural networks trained with a
% biologically plausible rule. Thomas Miconi (2016)"
% Published on BioRxiv. The current version can be found under the following URL:
% http://biorxiv.org/content/early/2016/07/26/057729
%
%
% INPUTS:
%
% x0 -- the initial activation (t == 0) of all neurons
% Must be of size: net.N x 1
%
% net -- the network structure created by hebbRNN_create_model
%
% F -- the desired output
% Must be a cell of size: 1 x conditions
% Each cell must be of size: net.B x time points
%
% perturbProb -- the probability of perturbing the activation of each neuron
% per second
%
% eta -- the learning rate
%
%
% OPTIONAL INPUTS:
%
% input -- the input to the network
% Must be a cell of size: 1 x conditions
% Each cell must be of size: net.I x time points
% Default: []
%
% targettimes -- the time points used to generate the error signal
% Default: entire trial
%
% beta -- the variance of the neural perturbation
% Default: 0.5. Don't change this unless you know what you're doing
%
% maxdJ -- the absolute connectivity values above this level will be
% clipped
% Default: 1e-4. Don't change this unless you know what you're doing
%
% alphaX -- the weight given to previous time points of the activation
% trace
% Default: 0. Don't change this unless you know what you're doing
%
% alphaR -- the weight given to previous time points of the error
% prediction trace
% Default: 0.33. Don't change this unless you know what you're doing
%
% targetFun -- the handle of a function that uses the firing rates of the
% output units to produce some desired output. Function must follow
% conventions of supplied default function.
% Default: @defaultTargetFunction
%
% targetFunPassthrough -- a user-defined structure that is automatically
% passed through to the targetFun, permitting custom variables to be passed
% Default: []
%
% tolerance -- at what error level below which the training will terminate
% Default: 0 (will train forever).
%
% batchType -- conditions are train either in random order each pass
% (pseudorand), or always in order (linear)
% Default: 'pseudorand'
%
% plotFun -- the handle of a function that plots information about the
% network during the learning process. Function must follow conventions
% of supplied default function.
% Default: @defaultPlottingFunction
%
% evalOpts -- a vector of size 2, specifying how much information should be
% displayed during training (0 - nothing, 1 - text only, 2 - text +
% figures), and how often the network should be evaluated. This vector is
% passed to the plotting function.
% Default: [0 50]
%
%
% OUTPUTS:
%
% net -- the network structure
%
% errStats -- the structure containing error information from learning
% (optional)
%
%
% Copyright (c) Jonathan A Michaels 2016
% German Primate Center
% jonathanamichaels AT gmail DOT com
%
% If used in published work please see repository README.md for citation
% and license information: https://github.com/JonathanAMichaels/hebbRNN


% Start counting
tic

% Variable output considerations
nout = max(nargout,1)-1;

% Variable input considerations
optargin = size(varargin,2);

inp = []; % Default inputs
mutationPowerDecay = 0.99;
mutationPowerDrop = 0.7;
targetFun = @defaultTargetFunction; % Default output function (native)
plotFun = @defaultPlottingFunction; % Default plotting function (native)
fitnessFun = @defaultFitnessFunction; % Default fitness function (native)
policyInitFun = @geneticRNN_create_model;
policyInitInputsOptional = [];
targetFunPassthrough = []; % Default passthrough to output function
evalOpts = [1 1]; % Default evaluation values [plottingOptions evaluateEveryXIterations]

for iVar = 1:2:optargin
    switch varargin{iVar}
        
        case 'input'
            inp = varargin{iVar+1};
            
        case 'mutationPowerDecay'
            mutationPowerDecay = varargin{iVar+1};
        case 'mutationPowerDrop'
            mutationPowerDrop = varargin{iVar+1};
            
        case 'fitnessFun'
            fitnessFun = varargin{iVar+1};
        case 'policyInitFun'
            policyInitFun = varargin{iVar+1};
        case 'policyInitInputsOptional'
            policyInitInputsOptional = varargin{iVar+1};
            
        case 'targetFun'
            targetFun = varargin{iVar+1};
        case 'targetFunPassthrough'
            targetFunPassthrough = varargin{iVar+1};
            
            
        case 'plotFun'
            plotFun = varargin{iVar+1};
        case 'evalOpts'
            evalOpts = varargin{iVar+1};
    end
end

%% Checks
% The input can be either empty, or specified at each time point by the user.

errStats.fitness = []; errStats.generation = []; % Initialize error statistics
g = 1;
previousGen = [];
decay = 1;

%% Main Program %%
% Runs until tolerated error is met or stop button is pressed
figure(97)
set(gcf, 'Position', [0 0 100 50], 'MenuBar', 'none', 'ToolBar', 'none', 'Name', 'Stop', 'NumberTitle', 'off')
UIButton = uicontrol('Style', 'togglebutton', 'String', 'STOP', 'Position', [0 0 100 50], 'FontSize', 25);
while UIButton.Value == 0
    tic
    fitness = zeros(length(inp),populationSize);
    bigR = cell(1,populationSize);
    bigZ1 = cell(1,populationSize);
    net = repmat(struct('I',0,'B',0,'N',0,'p',0,'g',0,'J',0,'netNoiseSigma',0,'dt',0,'tau',0,'wIn',0,'wFb',0,'wOut',0,'bJ',0,'bOut',0,'x0',0,'actFun',0,'actFunDeriv',0,'energyCost',0), ...
    1, populationSize);

    decay2 = mutationPower * 1e-1;
    parfor i = 1:populationSize
        if g == 1
            % Generate new networks
            net(i) = policyInitFun(policyInitInputs, policyInitInputsOptional);
        else
            if i == 1
                net(i) = previousGen(1);
            else
                k = randsample(truncationSize, 1);
                net(i) = previousGen(k);
                
                net(i).wIn = (net(i).wIn + (randn(size(net(i).wIn)) * mutationPower .* (net(i).wIn ~= 0))) .* (decay * ones(size(net(i).wIn)));
                net(i).wFb = (net(i).wFb + (randn(size(net(i).wFb)) * mutationPower .* (net(i).wFb ~= 0))) .* (decay * ones(size(net(i).wFb)));
                net(i).wOut = (net(i).wOut + (randn(size(net(i).wOut)) * mutationPower .* (net(i).wOut ~= 0))) .* (decay * ones(size(net(i).wOut)));
                net(i).J = (net(i).J + (randn(size(net(i).J)) * mutationPower .* (net(i).J ~= 0))) .* (decay * ones(size(net(i).J)));
                net(i).bJ = (net(i).bJ + (randn(size(net(i).bJ)) * mutationPower .* (net(i).bJ ~= 0))) .* (decay * ones(size(net(i).bJ)));
                net(i).bOut = (net(i).bOut + (randn(size(net(i).bOut)) * mutationPower .* (net(i).bOut ~= 0))) .* (decay * ones(size(net(i).bOut)));
                net(i).x0 = (net(i).x0 + (randn(size(net(i).x0)) * mutationPower .* (net(i).x0 ~= 0))) .* (decay * ones(size(net(i).x0)));
%                 
                net(i).wIn = net(i).wIn - decay2*(net(i).wIn-decay2 > 0) + decay2*(net(i).wIn+decay2 < 0);
                net(i).wFb = net(i).wFb - decay2*(net(i).wFb-decay2 > 0) + decay2*(net(i).wFb+decay2 < 0);
                net(i).wOut = net(i).wOut - decay2*(net(i).wOut-decay2 > 0) + decay2*(net(i).wOut+decay2 < 0);
                net(i).J = net(i).J - decay2*(net(i).J-decay2 > 0) + decay2*(net(i).J+decay2 < 0);
                net(i).bJ = net(i).bJ - decay2*(net(i).bJ-decay2 > 0) + decay2*(net(i).bJ+decay2 < 0);
                net(i).bOut = net(i).bOut - decay2*(net(i).bOut-decay2 > 0) + decay2*(net(i).bOut+decay2 < 0);
                net(i).x0 = net(i).x0 - decay2*(net(i).x0-decay2 > 0) + decay2*(net(i).x0+decay2 < 0);
                
%                 net(i).wIn(abs(net(i).wIn) <= decay2) = 0;
%                 net(i).wFb(abs(net(i).wFb) <= decay2) = 0;
%                 net(i).wOut(abs(net(i).wOut) <= decay2) = 0;
%                 net(i).J(abs(net(i).J) <= decay2) = 0;
%                 net(i).bJ(abs(net(i).bJ) <= decay2) = 0;
%                 net(i).bOut(abs(net(i).bOut) <= decay2) = 0;
%                 net(i).x0(abs(net(i).x0) <= decay2) = 0;
            end
        end
        
        % Run model
        [Z0, Z1, R, dR, ~] = geneticRNN_run_model(net(i), 'input', inp, 'targetFun', targetFun, 'targetFunPassthrough', targetFunPassthrough);
        % Assess fitness
        fitness(:,i) = fitnessFun(net(i).J, Z0, Z1, dR, fitnessFunInputs);
        
        bigZ1{i} = Z1;
        bigR{i} = R;
    end
    [~, sortInd] = sort(mean(fitness,1), 'descend');
    net = net(sortInd);
    fitness = fitness(:,sortInd(1:truncationSize));
    bigZ1 = bigZ1{sortInd(1)};
    bigR = bigR{sortInd(1)};
    
    if sortInd(1) == 1
        mutationPower = mutationPower * mutationPowerDrop;
    end
    
    %% Save stats
    errStats.fitness(:,end+1) = fitness(:,1);
    errStats.generation(end+1) = g;
    
    
    %% Populate statistics for plotting function
    plotStats.fitness = fitness;
    plotStats.mutationPower = mutationPower;
    plotStats.generation = g;
    plotStats.bigZ1 = bigZ1;
    plotStats.bigR = bigR;
    plotStats.targ = fitnessFunInputs;
    
    %% Run supplied plotting function
    if mod(g,evalOpts(2)) == 0
        plotFun(plotStats, errStats, evalOpts)
    end

    previousGen = net(1:truncationSize);
    mutationPower = mutationPower * mutationPowerDecay;
    g = g + 1;
    toc
end


%% Output error statistics if required
if ( nout >= 1 )
    varargout{1} = errStats;
end

%% Save hard-earned elite network
winner = previousGen(1);

disp('Training time required:')
toc

%% Default plotting function
    function defaultPlottingFunction(plotStats, errStats, evalOptions)
        if evalOptions(1) >= 0
            disp(['Generation: ' num2str(plotStats.generation) '  Fitness: ' num2str(mean(plotStats.fitness(:,1))) '  Mutation Power: ' num2str(plotStats.mutationPower)])
        end
        if evalOptions(1) >= 1
            figure(98)
            set(gcf, 'Name', 'Error', 'NumberTitle', 'off')
            c = lines(size(plotStats.fitness,1));
            for type = 1:size(plotStats.fitness,1)
                h1(type) = plot(plotStats.generation, plotStats.fitness(type,1), '.', 'MarkerSize', 20, 'Color', c(type,:));
                hold on
            end
            plot(plotStats.generation, mean(plotStats.fitness(:,1),1), '.', 'MarkerSize', 40, 'Color', [0 0 0]);
            set(gca, 'XLim', [1 plotStats.generation+0.1])
            xlabel('Generation')
            ylabel('Fitness')
        end
        if evalOptions(1) >= 2
            figure(99)
            set(gcf, 'Name', 'Output and Neural Activity', 'NumberTitle', 'off')
            clf
            subplot(4,1,1)
            hold on
            c = lines(length(plotStats.bigZ1));
            for condCount = 1:length(plotStats.bigZ1)
                h2(condCount,:) = plot(plotStats.bigZ1{condCount}', 'Color', c(condCount,:));
                h3(condCount,:) = plot(plotStats.targ{condCount}', '.', 'MarkerSize', 8, 'Color', c(condCount,:));
            end
            legend([h2(1,1) h3(1,1)], 'Network Output', 'Target Output', 'Location', 'SouthWest')
            xlabel('Time Steps')
            ylabel('Output')
            set(gca, 'XLim', [1 size(plotStats.bigZ1{1},2)])
            for n = 1:3
                subplot(4,1,n+1)
                hold on
                for condCount = 1:length(plotStats.bigR)
                    plot(plotStats.bigR{condCount}(n,:)', 'Color', c(condCount,:))
                end
                xlabel('Time Steps')
                ylabel(['Firing Rate (Neuron ' num2str(n) ')'])
                set(gca, 'XLim', [1 size(plotStats.bigR{1},2)])
            end
        end
        drawnow
    end

    function fitness = defaultFitnessFunction(J, Z0, Z1, dR, targ)
        fitness = zeros(1,length(Z1));
        for cond = 1:length(Z1)
            ind = ~isnan(targ{cond});
            
            useZ0 = Z0{cond};
            useZ1 = Z1{cond}(ind);
            usedR = dR{cond};
            useF = targ{cond}(ind);
            
            err(1) = sum(abs(useZ1(:)-useF(:)));
            %temp = J*usedR;
            err(2) = 0;%sum(temp(:).^2) / size(usedR,2);%0.0*sum(abs(useZ0(:)));
            
            fitness(cond) = -sum(err);
        end
    end
end