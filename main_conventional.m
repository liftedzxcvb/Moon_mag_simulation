%{
1: NLoS
2: OLCP
3: CLCP (comlink = 0)
4: CLCP (comlink = 1)
%}


% Can check the link state for each time slot with DLstate and ULstate


strongch = load('newstrongch.mat');
weakch = load('newweakch.mat');


% choose the channel by 'strongch.newstrongch' or 'weakch.newweakch'
ch = strongch.newstrongch;

T = 18000; % Total time

seed1 = floor(unifrnd(1,200000));
seed2 = seed1 + 110000;

fader = ones(T,1);
weather = 1.2;
%fader(12001:15000) = 1;

% generation of the random channels for each link
ch_B_up = ch.data_alp(seed1+1:seed1+T,1).*ch.data_bet(seed1+1:seed1+T,1).*fader.*weather;
ch_B_down = ch.data_alp(seed1+1:seed1+T,2).*ch.data_bet(seed1+1:seed1+T,2).*fader.*weather;
ch_C_up = ch.data_alp(seed2+1:seed2+T,1).*ch.data_bet(seed2+1:seed2+T,1).*fader.*weather;
ch_C_down = ch.data_alp(seed2+1:seed2+T,2).*ch.data_bet(seed2+1:seed2+T,2).*fader.*weather;

% attenuation
z = 2; % link distance in km
V = 3; % visibility range in km
if V > 50
    q_sca = 1.6;
elseif V > 6
    q_sca = 1.3;
else
    q_sca = 0.585 * V^(1/3);
end

sig_b = 3.91/V*(1550/550)^(-q_sca);

% attenuation
att = exp(-sig_b * z);

% communication aperture
a = 0.05; % m




ULstate = ones(T,1); % UL state (1~5)
DLstate = ones(T,1); % DL state (1~5)
P_B_uav = zeros(T,1); % beacon Rx power at UAV
P_C_uav = zeros(T,1); % commun Rx power at UAV
P_B_gw = zeros(T,1); % beacon Rx power at GW
P_C_gw = zeros(T,1); % commun Rx power at GW
PE_B_up = zeros(T,1); % beacon uplink PE
PE_C_up = zeros(T,1); % commun uplink PE
PE_B_down = zeros(T,1); % beacon donwlink PE
PE_C_down = zeros(T,1); % commun donwlink PE
PL_B_up = zeros(T,1); % beacon UL PL
PL_C_up = zeros(T,1); % commun UL PL
PL_B_down = zeros(T,1); % beacon DL PL
PL_C_down = zeros(T,1); % commun DL PL

powcheck = zeros(T,1);
fovcheck = zeros(T,1);

ULpow = zeros(T,1);
DLpow = zeros(T,1);
ULfov = zeros(T,1);
DLfov = zeros(T,1);

GNSS = 5/z; % mrad
OLGim = 3; % mrad
CLGim = 0.3; % mrad
OLthres = 0.0001; % W
FPAthres = 0.00000002; % W
QDthres = 0.0000001; % W
FPAfov = 40; % mrad
QDfov = 2; % mrad
BW_B = 5; % mrad
BW_C = 0.5; % mrad
T_B_uav = 0.5; % W
T_C_uav = 0.01; % W
T_B_gw = 1; % W
T_C_gw = 0.01; % W
driftcoeff = 0.10;
FSMres = 0.1; % mrad


los = ones(T,1);

PE_B_up(1:10) = 10;
PE_C_up(1:10) = 10;
PE_B_down(1:10) = 10;
PE_C_down(1:10) = 10;

zero = 99;
ULstate(1) = 1;
DLstate(1) = 1;
time = 10;
ULouton = 0;
DLouton = 0;
while time<T
    % drift due to UAV movement (downlink angular drift is larger due to
    % the angular motion of UAVs)
    dir = randphase();
    updrift = exprnd(0.2)*driftcoeff*dir;
    downdrift = exprnd(2)*driftcoeff*dir;
    % pointing error caused by the drift of the transmitter is assumed as a
    % linear movement for every 1s
    
    
    % when LoS is not guaranteed, pointing error is being cumulated without
    % being compensated
    if los(time) == 0
        % pointing errors are cumulated over time (every 0.1s)
        for i = 1:10
            time = time + 1;
            PE_B_up(time) = PE_B_up(time-1)+updrift;
            PE_C_up(time) = PE_C_up(time-1)+updrift;
            PE_B_down(time) = PE_B_down(time-1)+downdrift;
            PE_C_down(time) = PE_C_down(time-1)+downdrift;
            ULstate(time) = 1;
            DLstate(time) = 1;
        end
        
    % LoS is guaranteed (can try to establish the link)
    else
        % when LoS is achieved, the link prepares for the OLCP process at
        % the next coarse pointing loop
        if DLstate(time) == 1
            for i = 1:10
                time = time + 1;
                PE_B_up(time) = PE_B_up(time-1)+updrift;
                PE_C_up(time) = PE_C_up(time-1)+updrift;
                PE_B_down(time) = PE_B_down(time-1)+downdrift;
                PE_C_down(time) = PE_C_down(time-1)+downdrift;
                
                % Ready for the OLCP at the next loop
                ULstate(time) = 2;
                DLstate(time) = 2;
            end
        % when the beacon link is not connected, the link tries OLCP
        % (State 2 & 5)
        elseif (DLstate(time) == 2)|(ULstate(time) == 2)|(DLstate(time) == 5)|(ULstate(time) == 5)
            update = 0;
            
            % The angle estimation error for the UAV at the gateway
            estimation = compnum(GNSS) + compnum(OLGim);
            
            for i = 1:10
                time = time + 1;
                PE_C_up(time) = PE_C_up(time-1)+updrift;
                PE_C_down(time) = PE_C_down(time-1)+downdrift;
                PE_B_up(time) = estimation+updrift*(i-1);
                PE_B_down(time) = PE_B_down(time-1)+downdrift;
                
                % The received beacon power at the UAV is expressed as
                % Beacon Tx power * attenuation * random_channel * pointing loss
                P_B_uav(time) = T_B_gw * att * ch_B_up(time) * pe2pl(abs(PE_B_up(time)),BW_B,z,a);
                
                % when the received beacon power is higher than the OLCP
                % threshold power
                if P_B_uav(time) > OLthres
                    update = 1;
                end
                
                % update the state to 4 in order to start communication and
                % fine tracking
                if (update == 1)&(i==10)
                    ULstate(time) = 4;
                    DLstate(time) = 4;
                
                % if the OLCP is not successful, search for the UAV again
                % through the OLCP process
                else
                    ULstate(time) = 2;
                    DLstate(time) = 2;
                end
            end
            
            % When the OLCP is done and the link is maintained by the fine
            % tracking process, pointing errors are compensated by the FSM
            % and the residual error of the FSM control remains as a
            % pointing error of beacon/communication uplink/downlink
            if (ULstate(time) == 4)&(DLstate(time) == 4)
                PE_B_up(time) = compnum(FSMres);
                PE_B_down(time) = compnum(FSMres);
                PE_C_up(time) = compnum(FSMres);
                PE_C_down(time) = compnum(FSMres);
            end
            
        % both communication and beacon beam are well connected (State 4).
        % pointing errors are compensated by the FSM and the residual error
        % of the FSM control remains as a pointing error of
        % beacon/communicationn uplink/downlink
        else
            PE_B_up(time) = compnum(FSMres);
            PE_B_down(time) = compnum(FSMres);
            PE_C_up(time) = compnum(FSMres);
            PE_C_down(time) = compnum(FSMres);
            
            % check the received power
            for i = 1:10
                time = time + 1;
                
                % Rx power = Tx power * attenuation * random_channel * pointing loss
                P_B_uav(time) = T_B_gw * att * ch_B_up(time) * pe2pl(abs(PE_B_up(time-1)),BW_B,z,a);
                P_C_uav(time) = T_C_gw * att * ch_C_up(time) * pe2pl(abs(PE_C_up(time-1)),BW_C,z,a);
                P_B_gw(time) = T_B_uav * att * ch_B_down(time) * pe2pl(abs(PE_B_down(time-1)),BW_B,z,a);
                P_C_gw(time) = T_C_uav * att * ch_C_down(time) * pe2pl(abs(PE_C_down(time-1)),BW_C,z,a);
                
                % update pointing error
                PE_B_up(time) = PE_B_up(time-1)+updrift;
                PE_C_up(time) = PE_C_up(time-1)+updrift;
                PE_B_down(time) = PE_B_down(time-1)+downdrift;
                PE_C_down(time) = PE_C_down(time-1)+downdrift;
                
                
                
                % check DOWNLINK COMMUN. QD power threshold
                if P_C_uav(time) > QDthres % exceeds QD threshold power
                    PE_C_up(time) = compnum(FSMres);
                    ULstate(time) = 4;
                else % fine tracking outage
                    ULstate(time) = 3; % Deep fading
                    ULpow(time) = 1; 
                end
                
                % check UPLINK COMMUN. QD power threshold
                if P_C_gw(time) > QDthres % exceeds QD threshold power
                    PE_C_down(time) = compnum(FSMres);
                    DLstate(time) = 4;
                else % fine tracking outage
                    DLstate(time) = 3; % Deep fading
                    DLpow(time) = 1;
                end
                
                
                
                % check UPLINK FoV limit (FoV of FPA/QD at the UAV)
                
                % The pointing error can exceed the FoV of the detectors
                % due to the significant angular motion of the UAV or
                % severe misalignment of the control system
                
                % if the angle offset of the beacon receiver direction
                % exceeds the FPA FoV, the FPA cannot detect the uplink
                % beacon beam
                if fovout(PE_B_up(time),FPAfov)
                    ULstate(time) = 5; % UL link outage (FPA FoV)
                % if the angle offset of the communication receiver
                % direction exceeds the QD FoV, the FPA cannot detect the
                % uplink beacon beam
                elseif fovout(abs(PE_C_up(time)),QDfov)
                    % The UAV loses the uplink communication beam
                    % pointing
                    ULstate(time) = 3; % UL fine tracking outage (QD FoV)
                    ULfov(time) = 1;
                end
                
                % check DOWNLINK FoV limit (FoV of FPA/QD at the gateway)
                
                % if the angle offset of the beacon receiver direction
                % exceeds the FPA FoV, the FPA cannot detect the downlink
                % beacon beam
                if fovout(PE_B_down(time),FPAfov) 
                    % The UAV losses the downlink beacon pointing
                    DLstate(time) = 5; % DL link outage (FPA FoV)
                    fovcheck(time) = 1;
                % if the angle offset of the communication receiver
                % direction exceeds the QD FoV, the FPA cannot detect the
                % downlink beacon beam
                elseif fovout(abs(PE_C_down(time)),QDfov)
                    % The UAV loses the downlink communication beam
                    % pointing
                    DLstate(time) = 3; % DL fine tracking outage (QD FoV)
                    DLfov(time) = 1;
                end
                
                
                % check UPLINK BEACON FPA power threshold
                if P_B_uav(time) < FPAthres
                    ULouton = 1;
                end
                
                % check DOWNLINK BEACON FPA power threshold
                if P_B_gw(time) < FPAthres
                    DLouton = 1;
                end
                if ULouton==1
                    ULstate(time) = 5; % UL link outage (FPA power)
                end
                if DLouton==1
                    DLstate(time) = 5; % DL link outage (FPA power)
                    powcheck(time) = 1;
                end
            end
            ULouton = 0;
            DLouton = 0;

        end
    end
end

    
    plot(0.1:0.1:T/10,DLstate)
    
    ylabel('State number')
    xlabel('Time (second)')