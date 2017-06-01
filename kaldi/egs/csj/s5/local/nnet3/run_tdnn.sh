#!/bin/bash

# This is modified from swbd/s5c/local/nnet3/run_tdnn.sh
# Tomohiro Tanaka 15/05/2016

# this is the standard "tdnn" system, built in nnet3; it's what we use to
# call multi-splice.

. ./cmd.sh

# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.

train_stage=-10
stage=0
common_egs_dir=
reporting_email=
remove_egs=true

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1 
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA 
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

dir=exp/nnet3/nnet_tdnn
train_set=train_nodup
ali_dir=exp/tri4_ali_nodup
if [ -e data/train_dev ] ;then
    dev_set=train_dev
fi

local/nnet3/run_ivector_common.sh --stage $stage || exit 1;

if [ $stage -le 9 ]; then
  echo "$0: creating neural net configs";

  # create the config files for nnet initialization                                                                                                                                  
  python steps/nnet3/tdnn/make_configs.py  \
    --feat-dir data/${train_set}_hires \
    --ivector-dir exp/nnet3/ivectors_${train_set} \
    --ali-dir $ali_dir \
    --relu-dim 1024 \
    --splice-indexes "-2,-1,0,1,2 -1,2 -3,3 -7,2 0"  \
    --use-presoftmax-prior-scale true \
   $dir/configs || exit 1;
fi

if [ $stage -le 10 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi

  steps/nnet3/train_dnn.py --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.online-ivector-dir exp/nnet3/ivectors_${train_set} \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --trainer.num-epochs 2 \
    --trainer.optimization.num-jobs-initial 1 \
    --trainer.optimization.num-jobs-final 4 \
    --trainer.optimization.initial-effective-lrate 0.0017 \
    --trainer.optimization.final-effective-lrate 0.00017 \
    --egs.dir "$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --cleanup.preserve-model-interval 100 \
    --use-gpu true \
    --feat-dir=data/${train_set}_hires \
    --ali-dir $ali_dir \
    --lang data/lang \
    --reporting.email="$reporting_email" \
    --dir=$dir  || exit 1;

fi

graph_dir=exp/tri4/graph_csj_tg 
if [ $stage -le 11 ]; then
    for eval_num in $dev_set eval1 eval2 eval3 ; do
	steps/nnet3/decode.sh --nj 10 --cmd "$decode_cmd" \
            --online-ivector-dir exp/nnet3/ivectors_${eval_num} \
            $graph_dir data/${eval_num}_hires $dir/decode_${eval_num}_csj || exit 1;
    done
fi
wait;
exit 0;