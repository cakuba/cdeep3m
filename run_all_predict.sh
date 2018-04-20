#!/bin/bash

script_name=`basename $0`
script_dir=`dirname $0`
version="???"

if [ -f "$script_dir/VERSION" ] ; then
   version=`cat $script_dir/VERSION`
fi

gpu="0"
one_fmonly=false
aug_speed="1"

function usage()
{
    echo "usage: $script_name [-h] [--1fmonly] [--gpu GPU] [--augspeed AUGSPEED]

              Version: $version

              Runs caffe prediction on CDeep3M trained model using
              predict.config file to obtain location of trained
              model and image data

optional arguments:
  -h, --help           show this help message and exit
  --1fmonly            Only run prediction on 1fm model
  --augspeed           Augmentation speed. Higher the number
                       the less augmentations generated and
                       faster performance at cost of lower
                       accuracy. (valid values 1, 2, 4, 10)
                       (default 1)
  --gpu                Which GPU to use, can be a number ie 0 or 1
                       (default $gpu)

    " 1>&2;
   exit 1;
}

TEMP=`getopt -o h --long "1fmonly,gpu:,augspeed:" -n '$0' -- "$@"`
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h ) usage ;;
        --1fmonly ) one_fmonly=true ; shift ;;
        --gpu ) gpu=$2 ; shift 2 ;;
        --augspeed ) aug_speed=$2 ; shift 2 ;;
        --) break ;;
    esac
done

echo ""

# check aug_speed is a valid value
if [ "$aug_speed" -eq 1 ] || [ "$aug_speed" -eq 2 ] || [ "$aug_speed" -eq 4 ] || [ $aug_speed -eq 10 ] ; then
  : # the : is a no-op command
else
  echo "ERROR, --augspeed must be one of the following values 1, 2, 4, 10"
  exit 5
fi

predict_config="$script_dir/predict.config"

if [ ! -s "$predict_config" ] ; then
  echo "ERROR no $predict_config file found, which is required"
  exit 2
fi

trained_model_dir=`egrep "^ *trainedmodeldir *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

img_dir=`egrep "^ *augimagedir *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

echo "Running Prediction"
echo ""

echo "Trained Model Dir: $trained_model_dir"
echo "Image Dir: $img_dir"
echo ""

num_pkgs=`head -n 3 $img_dir/package_processing_info.txt | tail -n 1`
num_zstacks=`tail -n 1 $img_dir/package_processing_info.txt`


for Y in `find "$script_dir" -name "*fm" -type d | sort` ; do
 
  if [ $one_fmonly == true ] ; then
    if [ "$Y" != "$script_dir/1fm" ] ; then
       echo "--1fmonly flag set skipping prediction for $Y"
       continue
    fi
  fi

  for CUR_PKG in `seq 001 $num_pkgs` ; do
    for CUR_Z in `seq 01 $num_zstacks` ; do
      model_name=`basename $Y`
      echo "Running $model_name predict $num_pkgs package(s) to process"
      let cntr=1
      Z="$img_dir/$model_name/Pkg${CUR_PKG}_Z${CUR_Z}"
      if [ -f "$Z/DONE" ] ; then
        echo "Found $Z/DONE. Prediction completed. Skipping..."
        continue
      fi
      pkg_name=`basename $Z`
      outfile="$Z/out.log"
      PreprocessPackage.m 
      echo -n "  Processing $pkg_name $cntr of $num_pkgs "
      /usr/bin/time -p $script_dir/caffe_predict.sh --gpu $gpu "$trained_model_dir/$model_name/trainedmodel" "${img_dir}/${pkg_name}" "$Z"
      if [ $? != 0 ] ; then
        echo "Non zero exit code from caffe for predict $Z model. Exiting."
        if [ -f "$outfile" ] ; then
          echo "Here is last 10 lines of $outfile:"
          echo ""
          tail $outfile
        fi
        exit 3
      fi
      echo "Prediction completed: `date +%s`" > "$Z/DONE"
      let cntr+=1
    done
  if [ -f "$Y/DONE" ] ; then
    echo "Found $Y/DONE. Merge completed. Skipping..."
    continue
  fi
  echo ""
  echo "Running Merge_LargeData.m $Y"
  merge_log="$Y/merge.log"
  Merge_LargeData.m "$Y" >> "$merge_log" 2>&1
  ecode=$?
  if [ $ecode != 0 ] ; then
    echo "ERROR non-zero exit code ($ecode) from running Merge_LargeData.m"
    exit 4
  fi
  echo "Merge completed: `date +%s`" > "$Y/DONE"
done

echo ""
echo "Prediction has completed. Have a nice day!"
echo ""