module github.com/intel-secl/ta-sim

require (
	github.com/google/uuid v1.1.1
	github.com/intel-secl/intel-secl/v3 v3.4.0
	github.com/pkg/errors v0.9.1
	github.com/sirupsen/logrus v1.4.0
	github.com/spf13/viper v1.7.0
)

replace github.com/intel-secl/intel-secl/v3 => gitlab.devtools.intel.com/sst/isecl/intel-secl.git/v3 v3.4/develop
