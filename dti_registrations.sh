#!/bin/bash

#==============================================================================
#               NAME:  registrations.sh
#
#        DESCRIPTION:  This script takes, as an input directory, the
#                      individual participant's DTI directory that was passed
#                      to dti_preprocessing.sh and the MPRAGE directory that
#                      was passed to mprage_processing.sh. It then creates a 
#                      REG directory at the same level as the DTI directory
#                      called REG_<DTI_basename> or REG if the basename is 
#                      blank. This directory contains all the necessary
#                      transformations to get between the following spaces:
#                      DTI, FSL_highres, Freesurfer, MNI152.
#
#              USAGE:  registrations.sh <dti_data_folder> <mprage_data_folder>
#                           eg: registrations.sh ${dti_dir} ${mprage_dir}
#                           eg: registrations.sh /home/kw401/MRIMPACT/ANALYSES/1106/t1/DTI /home/kw401/MRIMPACT/ANALYSES/1106/t1/MPRAGE
#
#        PARAMETER 1:  DTI data folder (full path)
#                           If you're using this script as part of another
#                               eg: ${dti_dir}
#                           If you're using this script alone
#                               eg: /home/kw401/MRIMPACT/ANALYSES/1106/t1/DTI 
#
#        PARAMETER 2:  MPRAGE data folder (full path)
#                           If you're using this script as part of another
#                               eg: ${mprage_dir}
#                           If you're using this script alone
#                               eg: /home/kw401/MRIMPACT/ANALYSES/1106/t1/MPRAGE
#
#             AUTHOR:  Kirstie Whitaker
#                          kw401@cam.ac.uk
#
#            CREATED:  19th February 2013
#==============================================================================

#------------------------------------------------------------------------------
# Define usage function
function usage {
    echo "USAGE:"
    echo "registrations.sh <dti_data_folder> <mprage_data_folder>"
    echo "    eg: registrations.sh \${dti_dir} \${mprage_dir}"
    echo "    eg: registrations.sh /home/kw401/MRIMPACT/ANALYSES/1106/t1/DTI /home/kw401/MRIMPACT/ANALYSES/1106/t1/MPRAGE"
    exit
}
#------------------------------------------------------------------------------
 
#------------------------------------------------------------------------------
# Assign arguments
dti_dir=$1
if [[ ! -d /${dti_dir} ]]; then
    dir=`pwd`/${dti_dir}
fi

mprage_dir=$2
if [[ ! -d /${mprage_dir} ]]; then
    dir=`pwd`/${mprage_dir}
fi
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Check inputs

### Step 1: check arguments
# Exit if dti directory doesn't exist
if [[ ! -d ${dti_dir} ]]; then
    echo "    No DTI directory"
    print_usage=1
fi

# Exit if mprage directory doesn't exist
if [[ ! -d ${mprage_dir} ]]; then
    echo "    No MPRAGE directory"
    print_usage=1
fi


# Print the usage if necessary
if [[ ${print_usage} == 1 ]]; then
    usage
fi

### Step 2: Check data
# Make sure dti.nii.gz, bvals and bvecs_orig files exist
if [[ ! -f ${dir}/dti.nii.gz ]]; then
    if [[ -f ${dir}/dti.nii ]]; then
        gzip ${dir}/dti.nii
    else
        echo "    No dti.nii.gz file"
        print_usage=1
fi
if [[ ! -f ${dir}/bvals ]]; then
    echo "    No bvals file"
    print_usage=1
fi
if [[ ! -f ${dir}/bvecs_orig ]]; then
    echo "    No bvecs_orig file"
    print_usage=1
fi

# Print the usage if necessary
if [[ ${print_usage} == 1 ]]; then
    usage
fi
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Set up the rot_bvecs_script

# If you're Kirstie, then you're fine 
rot_bvecs_script=(/home/kw401/CAMBRIDGE_SCRIPTS/FSL_SCRIPTS/fdt_rotate_bvecs.sh)
if [[ ! -w ${rot_bvecs_script} ]]; then

    # Find out where this script is saved, and download the fdt_rotate_bvecs.sh
    # script into the same folder:
    scripts_dir="$( cd "$( dirname "$0" )" && pwd )"
    # (Handily stolen from http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in)

    rot_bvecs_script=${scripts_dir}/fdt_rotate_bvecs.sh

    wget -O ${rot_bvecs_script} https://github.com/HappyPenguin/FSL_COMMUNITY_CODE/blob/master/fdt_rotate_bvecs.sh

fi

# Make that script executable
chmod +x ${rot_bvecs_script}
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Get started
echo "DIR: ${dir}"
echo "SUBID: ${sub}"

# Make the LOGS dir
logdir=${dir}/LOGS
mkdir -p ${logdir}

#------------------------------------------------------------------------------
# Eddy correct to the first volume
if [[ ! -f ${dir}/dti_ec.nii.gz ]]; then
    echo "    Starting eddy correction step"
    rm -f ${dir}/dti_ec.ecclog
    eddy_correct ${dir}/dti.nii.gz ${dir}/dti_ec.nii.gz 0 > ${logdir}/eddycorrect
else
    echo "    Eddy correction step already completed"
fi

#------------------------------------------------------------------------------
# Rotate bvecs

if [[ ! -f ${dir}/bvecs ]]; then
    echo "    Rotating bvecs"
    ${rot_bvecs_script} ${dir}/bvecs_orig ${dir}/bvecs \
        ${dir}/dti_ec.ecclog >> ${logdir}/eddycorrect
else
    echo "    Bvecs already rotated"
fi

#------------------------------------------------------------------------------
# Brain extract
if [[ ! -f ${dir}/dti_ec.nii.gz ]]; then
    echo "    ERROR: Can't brain extract because eddy_correct has not been completed"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/dti_ec_brain.nii.gz ]]; then
    echo "    Brain extracting"
    bet ${dir}/dti_ec.nii.gz ${dir}/dti_ec_brain.nii.gz -f 0.15 -m > ${logdir}/bet

else
    echo "    Brain already extracted"
fi

#------------------------------------------------------------------------------
# DTIfit (FDT)
if [[ ! -f ${dir}/dti_ec_brain_mask.nii.gz || ! -f ${dir}/bvecs ]]; then
    echo "    ERROR: Can't fit tensor because brain extraction has not been completed"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/bvecs ]]; then
    echo "    ERROR: Can't fit tensor because bvecs file doesn't exist"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/FDT/${sub}_MO.nii.gz ]]; then
    echo "    Fitting tensor"
    mkdir -p ${dir}/FDT
    dtifit -k ${dir}/dti_ec.nii.gz \
        -m ${dir}/dti_ec_brain_mask.nii.gz \
        -r ${dir}/bvecs \
        -b ${dir}/bvals \
        -o ${dir}/FDT/${sub} \
        > ${logdir}/dtifit
    
    fslmaths ${dir}/FDT/${sub}_L2.nii.gz -add ${dir}/FDT/${sub}_L3.nii.gz -div 2 \
        ${dir}/FDT/${sub}_L23.nii.gz

else
   echo "    Tensor already fit"
fi

#------------------------------------------------------------------------------
# BedpostX
if [[ ! -f ${dir}/BEDPOSTX.bedpostX/dyads2.nii.gz ]]; then
    echo "    Now starting bedpostX"
    mkdir -p ${dir}/BEDPOSTX
    cp ${dir}/bvals ${dir}/BEDPOSTX/
    cp ${dir}/bvecs ${dir}/BEDPOSTX/
    cp ${dir}/dti_ec_brain_mask.nii.gz \
    ${dir}/BEDPOSTX/nodif_brain_mask.nii.gz
    cp ${dir}/dti_ec.nii.gz ${dir}/BEDPOSTX/data.nii.gz
    bedpostx ${dir}/BEDPOSTX/ > ${logdir}/bedpostx
else
    echo "    bedpostX already complete"
fi

#------------------------------------------------------------------------------
# TBSS 1 and 2
if [[ ! -f ${dir}/FDT/${sub}_FA.nii.gz ]]; then
    echo "    ERROR: Can't run TBSS as tensor has not been fit"
    echo "    EXITING"
    exit

elif [[ ! -f ${dir}/TBSS/FA/reverse_fnirt_warp.nii.gz ]]; then
    echo "    Now starting tbss"
    if [[ ! -f ${dir}/TBSS/FA/${sub}_FA_FA_to_target_warp.nii.gz ]]; then
        echo "    Running TBSS"
        rm -rf ${dir}/TBSS
        mkdir -p ${dir}/TBSS
        cp ${dir}/FDT/*FA* ${dir}/TBSS/
        cd ${dir}/TBSS/
        tbss_1_preproc * > ${logdir}/tbss
        tbss_2_reg -T >> ${logdir}/tbss
    fi
    # Now create the inverse fnirt warp
    echo "    Inverting FNIRT warp"
    if [[ -d ${dir}/TBSS/FA && \
           ! -f ${dir}/TBSS/FA/reverse_fnirt_warp.nii.gz ]]; then
        invwarp -r ${dir}/TBSS/FA/${sub}_FA_FA.nii.gz \
                -w ${dir}/TBSS/FA/${sub}_FA_FA_to_target_warp.nii.gz \
                -o ${dir}/TBSS/FA/reverse_fnirt_warp.nii.gz
    fi
else
    echo "    TBSS already complete"
fi

#------------------------------------------------------------------------------
# And you're done!
echo "--------------------------------"
#------------------------------------------------------------------------------