module intel/isecl/sgx_agent/v3

require (
	github.com/Waterdrips/jwt-go v3.2.1-0.20200915121943-f6506928b72e+incompatible
	github.com/google/uuid v1.1.2
	github.com/klauspost/cpuid v1.2.1
	github.com/pkg/errors v0.9.1
	github.com/sirupsen/logrus v1.4.0
	github.com/stretchr/testify v1.3.0
	gopkg.in/yaml.v2 v2.4.0
	intel/isecl/lib/clients/v3 v3.6.1
	intel/isecl/lib/common/v3 v3.6.1
)

replace (
	intel/isecl/lib/common/v3 => github.com/intel-secl/common/v3 v3.6.1
	intel/isecl/lib/clients/v3 => github.com/intel-secl/clients/v3 v3.6.1
)
