# TO-DOs for Dysconnect

[ ] BindableFunction support
[x] Batching all fires in a frame to a single packet to send to any clients to reduce Remote calls
[ ] Possibly assigning remote names an ID shared across all clients & server when setting a connection to send an int instead of the whole string so people don't have to worry much about name sizes
[ ] Separating the library into more submodules instead of one central module and only one submodule for DataType writing and reading, involving separate submodules for each side (C&S) and a shared module between the two, all children of a single central module containing the API calls.