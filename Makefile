PROJECT = emq_kafka_bridge
PROJECT_DESCRIPTION = EMQ Kafka Bridge
PROJECT_VERSION = 2.3.9.2

DEPS = ekaf
dep_ekaf = git https://github.com/helpshift/ekaf master


BUILD_DEPS = emqttd cuttlefish
dep_emqttd = git https://github.com/emqtt/emqttd master
dep_cuttlefish = git https://github.com/emqtt/cuttlefish

COVER = true

include erlang.mk

app:: rebar.config

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emq_kafka_bridge.conf -i priv/emq_kafka_bridge.schema -d data
