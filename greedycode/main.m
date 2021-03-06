clear
addpath('3rd_party/voc-release3.1/');           %% this code is downloaded from http://people.cs.uchicago.edu/~pff/latent/
addpath('3rd_party/cs2/');                      %% this code is downloaded from http://www.igsystems.com/cs2/index.html and then mex'ed to run faster in matlab.

mex -O 3rd_party/cs2/cs2mex.c -o 3rd_party/cs2/cs2mex     %% compiling c implementation of push-relabel algorithm. It is downloaded from http://www.igsystems.com/cs2/index.html and then we mex'ed it to run faster in matlab.

cd ('3rd_party/voc-release3.1')
compile                                         %% compiling mex files for part-based object detector
cd('../..');

mikeldata = 1 ;


if ~mikeldata
  datadir  = 'data/';
  cachedir = 'cache/';
  mkdir(cachedir);
  vid_name = 'seq03-img-left';
  gtname = 'seq03-img-left_ground_truth.mat' ;
  vid_path = [datadir vid_name '/'];
else
  datadir = 'mikeldata/' ;
  cachedir = 'mikelcache/' ;
  mkdir(cachedir) ;
  vid_name = 'first500' ;
  gtname = 'first500gt.mat' ;
  vid_path = [datadir vid_name '/'] ;
  trcname = 'Scene13_fullvid_pyl5_mind3_ssig1_new_15' ;
end

%%% Download and untar ETHZ dataset if not available. Needs to be done only once.
% if ~exist([vid_path 'image_00000100_0.png'])
%   display('Downloading ETHZ dataset (481MB)... (may take 15 minutes)')
%   cd('data/')
%   unix('wget http://www.vision.ee.ethz.ch/~aess/cvpr2008/seq03-img-left.tar.gz');
  
%   display('Untaring ETHZ dataset ...');
%   mkdir('seq03-img-left');
%   unix('tar -zxf seq03-img-left.tar.gz -C seq03-img-left');
%   unix('rm seq03-img-left.tar.gz');
%   cd ('..')
% end

%%% Run object/human detector on all frames.
display('in object/human detection... (may take an hour using 8 CPU cores: please set the number of available CPU cores in the code)')
fname = [cachedir vid_name '_detec_res.mat'];
try
  load(fname)
catch
  if ~mikeldata
    [dres bboxes] = detect_objects(vid_path);
  else
    [dres bboxes] = detect_objects_mikeldata(trcname) ;
  end
  save (fname, 'dres', 'bboxes');
end

%%% Adding transition links to the graph by fiding overlapping detections in consequent frames.
display('in building the graph...')
if ~mikeldata
  fname = [cachedir vid_name '_graph_res.mat']; % overlap
  % fname = [cachedir vid_name '_graph_res_win5_pyl2.mat']; % klt tracks
else
  % fname = [cachedir vid_name '_graph_res.mat'], overlap = 1 ; % overlap
  fname = [cachedir vid_name '_graph_res_pyl5_mind3_ssig1_new_15'], overlap = 0 ; % klt tracks ;
end

try
  load(fname)
catch
  if ~mikeldata
    % dres = build_graph_KLT_tracks(dres);
    dres = build_graph(dres) ;
  else
    dres = build_graph_mikeldata( 'Scene13_fullvid_pyl5_mind3_ssig1_new_15', dres, overlap ) ;
  end
  save (fname, 'dres');
end

%%% loading ground truth data
load([datadir gtname]);
% tmp2 = load('/meleze/data2/chari/Codes/CrowdAnalysis/Deva/tracking_cvpr11_release_v1.0/missing_gt2.mat') ;
% gt = tmp2.gt2 ;
% gt.x = [] ;
% gt.y = [] ;
% gt.w = [] ;
% gt.h = [] ;
% gt.fr = [] ;
% gt.vid = [] ;
% for i = min(tmp2.gt2.fr):max(tmp2.gt2.fr)
%   idxtmp = find( tmp2.gt2.fr == i ) ;
%   gt.x = [gt.x; tmp2.gt2.x(idxtmp)] ;
%   gt.y = [gt.y; tmp2.gt2.y(idxtmp)] ;
%   gt.w = [gt.w; tmp2.gt2.w(idxtmp)] ;
%   gt.h = [gt.h; tmp2.gt2.h(idxtmp)] ;
%   gt.fr = [gt.fr; tmp2.gt2.fr(idxtmp)] ;
%   gt.vid = [gt.vid; 3*ones(length(idxtmp),1)] ;
% end
if ~mikeldata
  people  = sub(gt,find((gt.w<24)|(gt.h<30)));    %% move small objects to "don't care" state in evaluation. This detector cannot detect these, so we will ignore false positives on them.
  gt      = sub(gt,find((gt.w>=24)&(gt.h>=30)));
else
  people.x = [] ;
  people.y = [] ;
  people.w = [] ;
  people.h = [] ;
  people.fr = [] ;
end

%%% setting parameters for tracking
c_en      = 10;     %% birth cost
c_ex      = 10;     %% death cost
c_ij      = 0;      %% transition cost
betta     = 0.2;    %% betta
max_it    = inf;    %% max number of iterations (max number of tracks)
thr_cost  = 100;     %% max acceptable cost for a track (increase it to have more tracks.)

%%% Running tracking algorithms
display('in DP tracking ...')
tic
dres_dp       = tracking_dp(dres, c_en, c_ex, c_ij, betta, thr_cost, max_it, 0);
dres_dp.r     = -dres_dp.id;
toc

tic
display('in DP tracking with nms in the loop...')
dres_dp_nms   = tracking_dp(dres, c_en, c_ex, c_ij, betta, thr_cost, max_it, 1);
dres_dp_nms.r = -dres_dp_nms.id;
toc

tic

display('in push relabel algorithm ...')
dres_push_relabel   = tracking_push_relabel(dres, c_en, c_ex, c_ij, betta, max_it);
dres_push_relabel.r = -dres_push_relabel.id;
toc
%%% We ignore the first frame in evaluation since there is no ground truth for it.
dres              = sub(dres,               find(dres.fr              >1));
dres_dp           = sub(dres_dp,            find(dres_dp.fr           >1));
dres_dp_nms       = sub(dres_dp_nms,        find(dres_dp_nms.fr       >1));
dres_push_relabel = sub(dres_push_relabel,  find(dres_push_relabel.fr >1));

%%% Evaluating
display('evaluating...')
[missr, fppi] = score(dres, gt, people, 'k');
figure(1), 
if ~mikeldata
  ff=find(fppi>3,1);
else
  ff = find(fppi>50, 1) ;
end
semilogx(fppi(1:ff),1-missr(1:ff), 'k');
hold on

[missr, fppi, finvaldp] = score(dres_dp, gt, people, 'r');
figure(1), semilogx(fppi,1-missr, 'r', 'LineWidth', 2);

[missr, fppi, finvaldpnms] = score(dres_dp_nms, gt, people, 'g');
figure(1), semilogx(fppi,1-missr, 'g');

[missr, fppi, finvaldpr] = score(dres_push_relabel, gt, people, 'b');
figure(1), semilogx(fppi,1-missr, 'b');

xlabel('False Positive Per Frame')
ylabel('Detection Rate')
legend('HOG', 'Dynamic Programming', 'NMS in the loop', 'Succesive shortest path', 'Linear Programming','location', 'NorthWest')
set(gcf, 'paperpositionmode','auto')
if ~mikeldata
  axis([0.001 5 0 1]) ;
else
  axis([0.001 50 0 1]) ;
end
grid
hold off

display('writing the results into a video file ...')

%%% uncomment this block if you want to re-build the label images. You don't need to do that unless there is more than 1000 tracks.
% close all
% % for i = 1:max(dres_dp.track_id)
% for i = 1:1000
%   bws(i).bw =  text_to_image(num2str(i), 20, 123);
% end
% save data/label_image_file bws

load([datadir 'label_image_file']);
m=2;
for i=1:length(bws)                   %% adds some margin to the label images
  [sz1 sz2] = size(bws(i).bw);
  bws(i).bw = [zeros(sz1+2*m,m) [zeros(m,sz2); bws(i).bw; zeros(m,sz2)] zeros(sz1+2*m,m)];
end

input_frames    = [datadir 'seq03-img-left/image_%0.8d_0.png'];
output_path     = [cachedir vid_name '_dp_tracked/'];
output_vidname  = [cachedir vid_name '_dp_tracked.avi'];

display(output_vidname)

fnum = max(dres.fr);
bboxes_tracked = dres2bboxes(dres_dp, fnum);  %% we are visualizing the "DP with NMS in the lop" results. Can be changed to show the results of DP or push relabel algorithm.
show_bboxes_on_video(input_frames, bboxes_tracked, output_vidname, bws, 4, -inf, output_path);
