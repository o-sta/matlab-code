%==========================================================================
% ◎ ドローンシステム同定
% CL-MOESP法でシステムを同定する
%==========================================================================
close all;
clear;
addpath('SI_Function');
%--------------------------------------------------------------------------
% ● 状態空間表現の定義
%--------------------------------------------------------------------------
syms Ix Iy Iz m g                 % 慣性モーメントと質量、重力加速度
load data/drone_ss;
load data/drone_data;
v_syms = [Ix Iy Iz m g];
v_vals = [drone_Ix drone_Iy drone_Iz drone_m drone_g];

%--------------------------------------------------------------------------
% ● 値の代入
%--------------------------------------------------------------------------
for i = 1:numel(v_syms)
  A = subs(A, v_syms(i), v_vals(i));
  B = subs(B, v_syms(i), v_vals(i));
  D = subs(D, v_syms(i), v_vals(i));
end
clear Ix Iy Iz m g;
Ix = v_vals(1);
Iy = v_vals(2);
Iz = v_vals(3);
m = v_vals(4);
g = v_vals(5);
c = 8.048*10^(-6);
l = 0.1785;
q = 2.423*19^(-7);

A_val = double(A);
B_val = double(B);
D_val = double(D);

%--------------------------------------------------------------------------
% ● パラメータ設定
% 最初の10秒(start_time)はシステムの収束のために使用され、次の10秒間(length_of_time)で
% システム同定に必要なデータを取得します。
%--------------------------------------------------------------------------
number_of_input = 4;                    % 入力の数 (ft tx ty tz)
number_of_output = 8;                   % 出力の数 (z w phi theta psi p q r)
number_of_state_variables = 8;          % 状態変数の数(9が一番良い)
number_of_rows_in_data_Matrix = 100;    % データ行列の行数
continuous_signal_ts = 0.001;           % 連続時間シミュレーションのサンプリング周期
                                        % (M系列連続信号のサンプリング周期)
simulation_sampling_ts = 0.001;         % 離散時間信号のサンプリング周期
start_time = 10;                        % 同定開始時間（M系列信号入力開始時間）
length_of_time = 20;                    % 同定に使用する時間
end_time = start_time + length_of_time; % 同定終了時間（シミュレーション終了時間）
min_value = [-3.0 -0.32 -0.32 -0.4];    % M系列信号の最小値 [ft tx ty tz]
max_value = -min_value;                 % M系列信号の最大値 [ft tx ty tz]
MLS_degree = 5;                         % M系列信号の次数

%--------------------------------------------------------------------------
% ● M系列信号作成
%--------------------------------------------------------------------------
% [continuous_signal, discrete_signal, ts] = 
% createMLS(number, seeds, min_value, max_value, length_of_time, continuous_signal_ts)
% continuous_signal     二値連続時間信号
% discrete_signal       二値離散時間信号
% ts                    二値離散時間信号のサンプリング周期
% number                number段シフトレジスタ（デフォルトは5）
% seeds                 シード値 seeds mod 2^number を2進数で表したものがレジスタの状態xの初期値になるが、
%                       0になったときはランダムにシードが選択される
% min_value             二値信号の最小値
% max                   二値信号の最大値
% length_of_time        信号全体の時間
% continuous_signal_ts  連続時間信号に格納するデータのサンプリング時間
%--------------------------------------------------------------------------
ft_signal = mf_createMLS(MLS_degree, 1, min_value(1), max_value(1), length_of_time, continuous_signal_ts);
tx_signal = mf_createMLS(MLS_degree, 2, min_value(2), max_value(2), length_of_time, continuous_signal_ts);
ty_signal = mf_createMLS(MLS_degree, 3, min_value(3), max_value(3), length_of_time, continuous_signal_ts);
tz_signal = mf_createMLS(MLS_degree, 4, min_value(4), max_value(4), length_of_time, continuous_signal_ts);

%--------------------------------------------------------------------------
% ● シミュレーション及びCL-MOESP実行
%--------------------------------------------------------------------------
sim('block/drone_nonlinear_full_identification', end_time);
data_discrete = getsampleusingtime(data_discrete, start_time, end_time);
reference_data = data_discrete.data(:, 27:30)'; % 目標値データ行列
input_data = data_discrete.data(:, 13:16)';     % 入力データ行列
% output_data = data_discrete.data(:, 1:12)';      % 出力データ行列(全部入り)
output_data = horzcat(data_discrete.data(:, 3),data_discrete.data(:, 6),data_discrete.data(:, 7:12))'; % 出力データ行列(xyuv除外)
% est_d_A : estimated discrete matrix A
[est_d_A, est_d_B, est_d_C, est_d_D] = mf_clmoesp(reference_data, input_data, output_data, number_of_rows_in_data_Matrix, number_of_state_variables);

%--------------------------------------------------------------------------
% ● データ比較
%--------------------------------------------------------------------------
% 時間を変える
length_of_time = 30;                    % 同定に使用する時間
end_time = start_time + length_of_time; % 同定終了時間（シミュレーション終了時間）
% M系列信号を同定時とは違うものにする
ft_signal = mf_createMLS(MLS_degree, 5, min_value(1), max_value(1), length_of_time, continuous_signal_ts);
tx_signal = mf_createMLS(MLS_degree, 6, min_value(2), max_value(2), length_of_time, continuous_signal_ts);
ty_signal = mf_createMLS(MLS_degree, 7, min_value(3), max_value(3), length_of_time, continuous_signal_ts);
tz_signal = mf_createMLS(MLS_degree, 8, min_value(4), max_value(4), length_of_time, continuous_signal_ts);

estimated_discrete_system = ss(est_d_A, est_d_B, est_d_C, est_d_D, simulation_sampling_ts);
estimated_continuous_system = d2c(estimated_discrete_system, 'zoh');
[est_c_A, est_c_B, est_c_C, est_c_D] = ssdata(estimated_continuous_system); % est_c_A : estimated continuous matrix A
matrix_A = est_c_C * est_c_A * est_c_C^(-1);
matrix_B = est_c_C * est_c_B;
matrix_C = est_c_C * est_c_C^(-1);
matrix_D = est_c_D;
est_c_A = matrix_A;
est_c_B = matrix_B;
est_c_C = matrix_C;
est_c_D = matrix_D;
sim('block/drone_nonlinear_full_compare', end_time);
%data_est = getsampleusingtime(data_est, start_time, end_time);

%--------------------------------------------------------------------------
% ● FIT算出
%--------------------------------------------------------------------------
data_est_discrete = getsampleusingtime(data_est_discrete, start_time, end_time);
fit_percent = [0 0 mf_fit(data_est_discrete.Data(:,3), data_est_discrete.Data(:,33)) ;
0 0 mf_fit(data_est_discrete.Data(:,6), data_est_discrete.Data(:,36));
mf_fit(data_est_discrete.Data(:,7), data_est_discrete.Data(:,37)) mf_fit(data_est_discrete.Data(:,8), data_est_discrete.Data(:,38)) mf_fit(data_est_discrete.Data(:,9), data_est_discrete.Data(:,39));
mf_fit(data_est_discrete.Data(:,10), data_est_discrete.Data(:,40)) mf_fit(data_est_discrete.Data(:,11), data_est_discrete.Data(:,41)) mf_fit(data_est_discrete.Data(:,12), data_est_discrete.Data(:,42));]

%--------------------------------------------------------------------------
% ● 推定行列の保存
% 状態をそのまま出力に持っていくと最適レギュレータのゲイン設計上都合が良いため、
% 行列Cを単位行列にする変換を施してから保存する
% 推定行列はmatrix_Aの形式で保存する
%--------------------------------------------------------------------------
% matrix_A = est_c_C * est_c_A * est_c_C^(-1);
% matrix_B = est_c_C * est_c_B;
% matrix_C = est_c_C * est_c_C^(-1);
% matrix_D = est_c_D;
save('data/estimated_matrix','matrix_A','matrix_B','matrix_C','matrix_D');

%--------------------------------------------------------------------------
% ● データのプロット
%--------------------------------------------------------------------------
fig1 = figure(1);
fig1.Position = [0 0 800 800];
% subplot(4,3,1)
% plot(data_est.time,data_est.data(:,1),'LineWidth',1.5) % x 1,1
% hold on
% plot(data_est.time,data_est.data(:,31),'--','LineWidth',1.5) % x 1,1
% xlabel('time [s]','FontName','arial','FontSize',10)
% ylabel('x [m]','FontName','arial','FontSize',10)
% subplot(4,3,2)
% plot(data_est.time,data_est.data(:,2),'LineWidth',1.5) % y 1,2
% hold on
% plot(data_est.time,data_est.data(:,32),'--','LineWidth',1.5) % x 1,1
% xlabel('time [s]','FontName','arial','FontSize',10)
% ylabel('y [m]','FontName','arial','FontSize',10)
subplot(4,3,3)
plot(data_est.time,data_est.data(:,3),'LineWidth',1.5) % z 1,3
hold on
plot(data_est.time,data_est.data(:,33),'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('z [m]','FontName','arial','FontSize',10)

% subplot(4,3,4)
% plot(data_est.time,data_est.data(:,4),'LineWidth',1.5) % u 2,1
% hold on
% plot(data_est.time,data_est.data(:,34),'--','LineWidth',1.5) % x 1,1
% xlabel('time [s]','FontName','arial','FontSize',10)
% ylabel('u [m/s]','FontName','arial','FontSize',10)
% subplot(4,3,5)
% plot(data_est.time,data_est.data(:,5),'LineWidth',1.5) % v 2,2
% hold on
% plot(data_est.time,data_est.data(:,35),'--','LineWidth',1.5) % x 1,1
% xlabel('time [s]','FontName','arial','FontSize',10)
% ylabel('v [m/s]','FontName','arial','FontSize',10)
subplot(4,3,6)
plot(data_est.time,data_est.data(:,6),'LineWidth',1.5) % w 2,3
hold on
plot(data_est.time,data_est.data(:,36),'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('w [m/s]','FontName','arial','FontSize',10)

subplot(4,3,7)
plot(data_est.time,data_est.data(:,7)*180/pi,'LineWidth',1.5) % phi 3,1
hold on
plot(data_est.time,data_est.data(:,37)*180/pi,'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('phi [deg]','FontName','arial','FontSize',10)
subplot(4,3,8)
plot(data_est.time,data_est.data(:,8)*180/pi,'LineWidth',1.5) % theta 3,2
hold on
plot(data_est.time,data_est.data(:,38)*180/pi,'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('theta [deg]','FontName','arial','FontSize',10)
subplot(4,3,9)
plot(data_est.time,data_est.data(:,9)*180/pi,'LineWidth',1.5) % psi 3,3
hold on
plot(data_est.time,data_est.data(:,39)*180/pi,'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('psi [deg]','FontName','arial','FontSize',10)

subplot(4,3,10)
plot(data_est.time,data_est.data(:,10)*180/pi,'LineWidth',1.5) % p 4,1
hold on
plot(data_est.time,data_est.data(:,40)*180/pi,'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('p [deg/s]','FontName','arial','FontSize',10)
subplot(4,3,11)
plot(data_est.time,data_est.data(:,11)*180/pi,'LineWidth',1.5) % q 4,2
hold on
plot(data_est.time,data_est.data(:,41)*180/pi,'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('q [deg/s]','FontName','arial','FontSize',10)
subplot(4,3,12)
plot(data_est.time,data_est.data(:,12)*180/pi,'LineWidth',1.5) % r 4,3
hold on
plot(data_est.time,data_est.data(:,42)*180/pi,'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('r [deg/s]','FontName','arial','FontSize',10)
movegui('northwest')

fig2 = figure(2);
fig2.Position = [0 0 400 800];
subplot(4,1,1)
plot(data_est.time,data_est.data(:,13),'LineWidth',1.5) % ft 1
hold on
plot(data_est.time,data_est.data(:,43),'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('ft [N]','FontName','arial','FontSize',10)
subplot(4,1,2)
plot(data_est.time,data_est.data(:,14),'LineWidth',1.5) % fx 2
hold on
plot(data_est.time,data_est.data(:,44),'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('tx [N]','FontName','arial','FontSize',10)
subplot(4,1,3)
plot(data_est.time,data_est.data(:,15),'LineWidth',1.5) % fy 3
hold on
plot(data_est.time,data_est.data(:,45),'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('ty [N]','FontName','arial','FontSize',10)
subplot(4,1,4)
plot(data_est.time,data_est.data(:,16),'LineWidth',1.5) % fz 4
hold on
plot(data_est.time,data_est.data(:,46),'--','LineWidth',1.5) % x 1,1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('tz [N]','FontName','arial','FontSize',10)
iptwindowalign(fig1,'right',fig2,'left');

fig3 = figure(3);
fig3.Position = [0 0 400 800];
subplot(4,1,1)
plot(data_est.time,data_est.data(:,27),'LineWidth',1.5) % desire_z 1
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('signal ft [N]','FontName','arial','FontSize',10)
subplot(4,1,2)
plot(data_est.time,data_est.data(:,28),'LineWidth',1.5) % desire_phi 2
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('signal tx [Nm]','FontName','arial','FontSize',10)
subplot(4,1,3)
plot(data_est.time,data_est.data(:,29),'LineWidth',1.5) % desire_theta 3
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('signal ty [Nm]','FontName','arial','FontSize',10)
subplot(4,1,4)
plot(data_est.time,data_est.data(:,30),'LineWidth',1.5) % desire_psi 4
xlabel('time [s]','FontName','arial','FontSize',10)
ylabel('signal tz [Nm]','FontName','arial','FontSize',10)
iptwindowalign(fig2,'right',fig3,'left');

% saveas(fig1,'figdata/id2_state','pdf');
% saveas(fig2,'figdata/id2_input','pdf');
% saveas(fig3,'figdata/id2_signal','pdf');

