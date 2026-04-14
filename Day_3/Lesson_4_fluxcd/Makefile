setup: setup-cluster setup-flux
	@ git pull

setup-cluster:
	@ registry_up
	@ kind_up

setup-flux: setup-cluster
	@ flux install

teardown:
	kind_down
	registry_down
