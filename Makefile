
.PHONY: all clean terraform-bundle spigot lambda update plan info

all: update

clean:
	@echo Just run git clean -xdfn then git clean -xdf

terraform-bundle:
	go get github.com/hashicorp/terraform
	go install github.com/hashicorp/terraform/tools/terraform-bundle
	cd terraform && $(shell go env GOPATH)/bin/terraform-bundle package -os=linux -arch=amd64 terraform-bundle.hcl

spigot:
	@echo This may take a 5-10 minutes
	mkdir -p spigot-build spigot-bin
	cd spigot-build && curl -OL 'https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar'
	cd spigot-build && java -jar BuildTools.jar
	cp spigot-build/spigot*jar spigot-bin/
	cd spigot-bin && aws s3 sync . s3://$(shell cat core/terraform.tfvars | python -c 'import sys,json;print(json.load(sys.stdin)[sys.argv[1]])' aws_s3_world_backup)

lambda: core/lambda_status.zip

core/lambda_status.zip: core/lambda_status/lambda_status.py core/lambda_status/requirements.txt
	cd core/lambda_status && [ ! -f ./venv/bin/activate ] && virtualenv venv || true
	cd core/lambda_status && . ./venv/bin/activate && pip install -r requirements.txt
	cd core/lambda_status && ( cd ./venv/lib/python*/site-packages; zip -r9 - * ) > ../lambda_status.zip
	cd core/lambda_status && zip -g ../lambda_status.zip lambda_status.py

update: lambda
	cd core && terraform apply
	cd core && terraform output -json > ../instance/terraform.tfvars.json
	cd instance && aws s3 sync --delete . s3://$(shell cat core/terraform.tfvars | awk -vFS='=' '/aws_s3_terraform_plan/{gsub(/[" ]/,"");print $$2}')

plan: lambda
	cd core && terraform plan

info:
	cd core && terraform output
