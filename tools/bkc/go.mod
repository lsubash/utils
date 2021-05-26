module intel/isecl/tools/bkc/v4

require (
	github.com/google/uuid v1.1.1
	github.com/intel-secl/intel-secl/v4 v4.0.0
	github.com/klauspost/cpuid v1.3.1
	github.com/pkg/errors v0.9.1
	intel/isecl/lib/common/v4 v4.0.0
	intel/isecl/lib/platform-info/v4 v4.0.0
	intel/isecl/lib/tpmprovider/v4 v4.0.0

	github.com/vmware/govmomi v0.22.2
)

replace intel/isecl/lib/common/v4 => gitlab.devtools.intel.com/sst/isecl/lib/common.git/v4 v4.0/develop

replace intel/isecl/lib/tpmprovider/v4 => gitlab.devtools.intel.com/sst/isecl/lib/tpm-provider.git/v4 v4.0/develop

replace intel/isecl/lib/platform-info/v4 => gitlab.devtools.intel.com/sst/isecl/lib/platform-info.git/v4 v4.0/develop

replace github.com/vmware/govmomi => github.com/arijit8972/govmomi fix-tpm-attestation-output
