#!/bin/bash


export PROJ_NAME="DAT307"
#export GITHUB_NAME="aurora-postgresql-pgvector"
#export GITHUB_URL="https://github.com/aws-samples/"
export GITHUB_NAME="github-dat307"
export GITHUB_URL="https://github.com/ajrajkumar/"
export PYTHON_MAJOR_VERSION="3.12"
export PYTHON_MINOR_VERSION="1"
export PYTHON_VERSION="${PYTHON_MAJOR_VERSION}.${PYTHON_MINOR_VERSION}"
export PGVERSION="16.3"
export BASEDIR=${HOME}/environment/${PROJ_NAME}
export AWS_PAGER=""


function print_line()
{
    echo "---------------------------------"
}

function install_packages()
{
    sudo yum install -y jq  > ${TERM} 2>&1
    print_line
    source <(curl -s https://raw.githubusercontent.com/aws-samples/aws-swb-cloud9-init/mainline/cloud9-resize.sh)
    echo "Installing aws cli v2"
    print_line
    aws --version | grep aws-cli\/2 > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        cd $current_dir
	return
    fi
    current_dir=`pwd`
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" > ${TERM} 2>&1
    unzip -o awscliv2.zip > ${TERM} 2>&1
    sudo ./aws/install --update > ${TERM} 2>&1
    cd $current_dir
}

function install_postgresql()
{
    print_line
    echo "Installing Postgresql client"
    print_line
    sudo yum install -y readline-devel zlib-devel gcc
    if [ ! -f /usr/local/pgsql/bin/psql ] ; then
        cd /tmp
        wget https://ftp.postgresql.org/pub/source/v${PGVERSION}/postgresql-${PGVERSION}.tar.gz > ${TERM} 2>&1
        tar -xvf postgresql-${PGVERSION}.tar.gz > ${TERM} 2>&1
        cd postgresql-${PGVERSION}
        ./configure --without-icu > ${TERM} 2>&1
        make > ${TERM} 2>&1
        sudo make install > ${TERM} 2>&1
    else
	echo "PostgreSQL already installed.. skipping"
    fi

    sudo amazon-linux-extras install -y postgresql14 > ${TERM} 2>&1
    sudo yum install -y postgresql-contrib sysbench > ${TERM} 2>&1

}

function clone_git()
{
    print_line
    echo "Cloning the git repository"
    print_line
    cd ${HOME}/environment
    git clone ${GITHUB_URL}${GITHUB_NAME}
    mv ${GITHUB_NAME}/${PROJ_NAME}  ${HOME}/environment
    rm -rf ${GITHUB_NAME}
    cd ${PROJ_NAME}
    print_line
}


function configure_env()
{
    #AWS_REGION=`aws configure get region`

    PGHOST=`aws rds describe-db-cluster-endpoints \
        --db-cluster-identifier apgpg-pgvector \
        --region $AWS_REGION \
        --query 'DBClusterEndpoints[0].Endpoint' \
        --output text`
    export PGHOST

    # Retrieve credentials from Secrets Manager - Secret: apgpg-pgvector-secret
    CREDS=`aws secretsmanager get-secret-value \
        --secret-id apgpg-pgvector-secret \
        --region $AWS_REGION | jq -r '.SecretString'`

    PGPASSWORD="`echo $CREDS | jq -r '.password'`"
    if [ "${PGPASSWORD}X" == "X" ]; then
        PGPASSWORD="postgres"
    fi
    export PGPASSWORD

    PGUSER="postgres"
    PGUSER="`echo $CREDS | jq -r '.username'`"
    if [ "${PGUSER}X" == "X" ]; then
        PGUSER="postgres"
    fi
    export PGUSER

    export APIGWURL=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'APIGatewayURL')][].{OutputValue:OutputValue}" --output text)
    export APIGWSTAGE=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'APIGatewayStage')][].{OutputValue:OutputValue}" --output text)
    export APP_CLIENT_ID=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'CognitoClientID')][].{OutputValue:OutputValue}" --output text)

    export KB_IDR_S3=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBIDRS3SourceBucketName')][].{OutputValue:OutputValue}" --output text)
    export KB_QA_S3=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBQAS3SourceBucketName')][].{OutputValue:OutputValue}" --output text)

    export C9_URL="https://\${C9_PID}.vfs.cloud9.${AWS_REGION}.amazonaws.com/"

    # Persist values in future terminals
    echo "export PGUSER=$PGUSER" >> /home/ec2-user/.bashrc
    echo "export PGPASSWORD='$PGPASSWORD'" >> /home/ec2-user/.bashrc
    echo "export PGHOST=$PGHOST" >> /home/ec2-user/.bashrc
    echo "export AWS_REGION=$AWS_REGION" >> /home/ec2-user/.bashrc
    echo "export AWSREGION=$AWS_REGION" >> /home/ec2-user/.bashrc
    echo "export PGDATABASE=postgres" >> /home/ec2-user/.bashrc
    echo "export PGPORT=5432" >> /home/ec2-user/.bashrc
    echo "export PATH=/usr/local/pgsql/bin:\${PATH}" >> /home/ec2-user/.bashrc
    echo "export APIGWURL=${APIGWURL}" >> /home/ec2-user/.bashrc
    echo "export APIGWSTAGE=${APIGWSTAGE}" >> /home/ec2-user/.bashrc
    echo "export APP_CLIENT_ID=${APP_CLIENT_ID}" >> /home/ec2-user/.bashrc
    echo "export C9_URL=${C9_URL}" >> /home/ec2-user/.bashrc
    echo "export KB_IDR_S3=${KB_IDR_S3}" >> /home/ec2-user/.bashrc
    echo "export KB_QA_S3=${KB_QA_S3}" >> /home/ec2-user/.bashrc
}

function install_extension()
{
    psql -h ${PGHOST} -c "create extension if not exists vector"
}

function install_python3()
{
    # Install Python 3
    sudo yum remove -y openssl-devel > ${TERM} 2>&1
    sudo yum install -y gcc openssl11-devel bzip2-devel libffi-devel  > ${TERM} 2>&1

    echo "Checking if python${PYTHON_MAJOR_VERSION} is already installed"
    if [ -f /usr/local/bin/python${PYTHON_MAJOR_VERSION} ] ; then 
        echo "Python${PYTHON_MAJOR_VERSION} already exists"
	return
    fi

    cd /opt
    echo "Installing python ${PYTHON_VERSION}"
    sudo wget https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz  > ${TERM} 2>&1
    sudo tar xzf Python-${PYTHON_VERSION}.tgz  > ${TERM} 2>&1
    cd Python-${PYTHON_VERSION}
    sudo ./configure --enable-optimizations  > ${TERM} 2>&1
    sudo make altinstall  > ${TERM} 2>&1
    sudo rm -f /opt/Python-{$PYTHON_VERSION}.tgz
    pip${PYTHON_MAJOR_VERSION} install --upgrade pip  > ${TERM} 2>&1

    # Installing required modules
    
    pip${PYTHON_MAJOR_VERSION} install boto3 psycopg2-binary requests  > ${TERM} 2>&1

    echo "Making this version of python as default"
    sudo rm /usr/bin/python3
    sudo ln -s /usr/local/bin/python${PYTHON_MAJOR_VERSION} /usr/bin/python3 
}

function install_c9()
{
    print_line
    echo "Installing c9 executable"
    sudo npm install -g c9
    print_line
}


function check_installation()
{
    overall="True"
    #Checking postgresql 
    psql -c "select version()" | grep PostgreSQL > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo "PostgreSQL installation successful : OK"
    else
        echo "PostgreSQL installation FAILED : NOTOK"
	overall="False"
    fi
    
    # Checking clone
    if [ -d ${HOME}/environment/${PROJ_NAME}/ ] ; then 
        echo "Git Clone successful : OK"
    else
        echo "Git Clone FAILED : NOTOK"
	overall="False"
    fi
   
    # Checking c9
    
    c9 --version > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo "C9 installation successful : OK"
    else
        echo "C9 installation FAILED : NOTOK"
	overall="False"
    fi

    # Checking python
    /usr/local/bin/python${PYTHON_MAJOR_VERSION} --version | grep Python  > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo "Python installation successful : OK"
    else
        echo "Python installation FAILED : NOTOK"
	overall="False"
    fi

    # Checking python3
    python3 --version | grep ${PYTHON_VERSION}  > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo "Python default installation successful : OK"
    else
        echo "Python default installation FAILED : NOTOK"
	overall="False"
    fi


    echo "=================================="
    if [ ${overall} == "True" ] ; then
        echo "Overall status : OK"
    else
        echo "Overall status : FAILED"
    fi
    echo "=================================="

}

function upload_kb()
{
    export KBIDRS3=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBIDRS3SourceBucketName')][].{OutputValue:OutputValue}" --output text)
    export KBQAS3=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBQAS3SourceBucketName')][].{OutputValue:OutputValue}" --output text)
    export KBIDRSOURCEID=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBIDRSourceID')][].{OutputValue:OutputValue}" --output text)
    export KBQASOURCEID=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBQASourceID')][].{OutputValue:OutputValue}" --output text)
    export KBIDRID=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBIDRID')][].{OutputValue:OutputValue}" --output text)
    export KBQAID=$(aws cloudformation describe-stacks --query "Stacks[].Outputs[?(OutputKey == 'KBQAID')][].{OutputValue:OutputValue}" --output text)

    KBIDRSOURCE=`echo ${KBIDRSOURCEID} | awk -F'|' '{print $2}'`
    ls -1 ${BASEDIR}/knowledge-base/runbooks/*.md | while read file
    do
        echo "File is ${file}"
        aws s3 cp "${file}" s3://${KBIDRS3}
    done

    KBQASOURCE=`echo ${KBQASOURCEID} | awk -F'|' '{print $2}'`
    ls -1 ${BASEDIR}/knowledge-base/documents/*.pdf | while read file
    do
        echo "File is ${file}"
        aws s3 cp "${file}" s3://${KBQAS3}
    done

    aws bedrock-agent start-ingestion-job --data-source-id ${KBIDRSOURCE} --knowledge-base-id ${KBIDRID}
    echo "aws bedrock-agent start-ingestion-job --data-source-id ${KBIDRSOURCE} --knowledge-base-id ${KBIDRID}"
    aws bedrock-agent start-ingestion-job --data-source-id ${KBQASOURCE} --knowledge-base-id ${KBQAID}
    echo "aws bedrock-agent start-ingestion-job --data-source-id ${KBQASOURCE} --knowledge-base-id ${KBQAID}"

}


function install_lambda()
{

    for lambda in cw-ingest-to-dynamodb idr-bedrock-agent-action-group qa-bedrock-agent-action-group api-get-incidents api-list-runbook-kb api-action-runbook-kb
    do
        rm -rf /tmp/${lambda}
        mkdir /tmp/${lambda}
        cp ${BASEDIR}/lambda/${lambda}.py /tmp/${lambda}/index.py
        cd /tmp/${lambda}
        zip -r ${lambda}.zip index.py
        aws lambda update-function-code --function-name  ${lambda}  --zip-file fileb:///tmp/${lambda}/${lambda}.zip
    done

}

function cp_logfile()
{
    bucket_name="genai-pgv-labs-${AWS_ACCOUNT_ID}-`date +%s`"
    echo ${bucket_name}
    aws s3 ls | grep ${bucket_name} > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
        aws s3 mb s3://${bucket_name} --region ${AWS_REGION}
    fi

    aws s3 cp ${HOME}/environment/prereq.log s3://${bucket_name}/prereq_${AWS_ACCOUNT_ID}.txt > /dev/null 
    if [ $? -eq 0 ] ; then
	echo "Copied the logfile to bucket ${bucket_name}"
    else
	echo "Failed to copy logfile to bucket ${bucket_name}"
    fi
}
# Main program starts here

if [ ${1}X == "-xX" ] ; then
    TERM="/dev/tty"
else
    TERM="/dev/null"
fi

echo "Process started at `date`"
install_packages

export AWS_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r`
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) 
 
install_postgresql
clone_git
configure_env
install_extension
print_line
install_c9
print_line
install_python3
print_line
install_lambda
print_line
# KB will be uploaded by the participants
#upload_kb
check_installation
cp_logfile

echo "Process completed at `date`"
