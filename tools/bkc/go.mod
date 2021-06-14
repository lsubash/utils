module intel/isecl/tools/bkc/v3

require (
	github.com/google/uuid v1.1.1
	github.com/intel-secl/intel-secl/v3 v3.6.0
	github.com/klauspost/cpuid v1.3.1
	github.com/pkg/errors v0.9.1
	intel/isecl/lib/common/v3 v3.6.0
	intel/isecl/lib/platform-info/v3 v3.6.0
	intel/isecl/lib/tpmprovider/v3 v3.6.0
)

replace (
	github.com/intel-secl/intel-secl/v3 => gitlab.devtools.intel.com/sst/isecl/intel-secl.git/v3 v3.6.0
	intel/isecl/lib/common/v3 => gitlab.devtools.intel.com/sst/isecl/lib/common.git/v3 v3.6.0
	intel/isecl/lib/platform-info/v3 => gitlab.devtools.intel.com/sst/isecl/lib/platform-info.git/v3 v3.6.0
	intel/isecl/lib/tpmprovider/v3 => gitlab.devtools.intel.com/sst/isecl/lib/tpm-provider.git/v3 v3.6.0
)
