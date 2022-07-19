etcd-cpp-apiv3
==============

The _etcd-cpp-apiv3_ is a C++ API for [etcd](https://etcd.io/)'s v3 client API,
i.e., `ETCDCTL_API=3`.

[![Build and Test](https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3/workflows/Build%20and%20Test/badge.svg)](https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3/actions?workflow=Build+and+Test)

### Supported OS environments

+ **Linux**
  - Ubuntu 18.04, requires upgrade gRPC libraries (tested with 1.27.x).
  - Ubuntu 20.04
  - CentOS 8 (tested with 1.27.x)

+ **MacOS**
  - MacOS 10.15
  - MacOS 11.0

+ **Windows**
  - Windows 10, with [vcpkg](https://github.com/microsoft/vcpkg)

### Supported etcd versions:

+ etcd 3.2, tested with [v3.2.26](https://github.com/etcd-io/etcd/releases/v3.2.26)
+ etcd 3.3, tested with [v3.3.11](https://github.com/etcd-io/etcd/releases/v3.3.11)
+ etcd 3.4, tested with [v3.4.13](https://github.com/etcd-io/etcd/releases/v3.4.13)

## Requirements

1. boost and openssl

   + On Ubuntu, above requirement could be installed as:

         apt-get install libboost-all-dev libssl-dev

   + On MacOS, above requirement could be installed as:

         brew install boost openssl

2. protobuf
3. gRPC

   + On Ubuntu, above requirements related to protobuf and gRPC can be installed as:

         apt-get install libgrpc-dev \
                 libgrpc++-dev \
                 libprotobuf-dev \
                 protobuf-compiler-grpc
        
   + On MacOS, above requirements related to protobuf and gRPC can be installed as:


         brew install grpc protobuf


4. [cpprestsdk](https://github.com/microsoft/cpprestsdk), the latest version of master branch
   on github should work, you can build and install this dependency using cmake with:

        git clone https://github.com/microsoft/cpprestsdk.git
        cd cpprestsdk
        mkdir build && cd build
        cmake .. -DCPPREST_EXCLUDE_WEBSOCKETS=ON
        make -j && make install

## Build and install

The _etcd-cpp-apiv3_ library could be easily built and installed using cmake, after all above
dependencies have been successfully installed:

    git clone https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3.git
    cd etcd-cpp-apiv3
    mkdir build && cd build
    cmake ..
    make -j && make install

## Compatible etcd version

The _etcd-cpp-apiv3_ should work well with etcd > 3.0. Feel free to issue an issue to us on
Github when you encounter problems when working with etcd 3.x releases.

## Sync vs. Async runtime

There are various discussion about whether to support a user-transparent multi-thread executor in
the background, or, leaving the burden of thread management to the user (e.g., see
[issue#100](https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3/issues/100) for more discussion about
the implementation of underlying thread model).

The _etcd-cpp-apiv3_ library supports both synchronous and asynchronous runtime, in two separate
library as follows:

- etcd-cpp-api-core: the synchronous runtime, provides a blocking-style API and the users are responsible
  for handling dispatch the request into separate thread to avoid been blocked by waiting for response.
  - target found by cmake: `ETCD_CPP_CORE_LIBRARIES`

- etcd-cpp-api: the asynchronous runtime backed by the `pplx` library from
  [cpprestsdk](https://github.com/microsoft/cpprestsdk), where a `boost::asio::io_context` and a pool
  of threads is used to run the asynchronous operations in the background. By default the number of
  threads in the thread pool equals to `std::thread::hardware_concurrency()`.
  - target found by cmake: `ETCD_CPP_LIBRARIES`

We encourage the users to use the asynchronous runtime by default, as it provides more flexibility
and convenient APIs and less possibilities for errors that block the main thread. However, please note
that the asynchronous runtime will setup a thread pool in the background.

Note that `etcd-cpp-api-core` and `etcd-cpp-api` are two separate target and don't depends on each other.
You should depends on either of them in your program.

## Usage

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  etcd::Response response = etcd.get("/test/key1").get();
  std::cout << response.value().as_string();
```

Methods of the etcd client object are sending the corresponding gRPC requests and are returning
immediately with a `pplx::task` object. The task object is responsible for handling the
reception of the HTTP response as well as parsing the gRPC of the response. All of this is done
asynchronously in a background thread so you can continue your code to do other operations while the
current etcd operation is executing in the background or you can wait for the response with the
`wait()` or `get()` methods if a synchronous behavior is enough for your needs. These methods
are blocking until the HTTP response arrives or some error situation happens. `get()` method
also returns the `etcd::Response` object.

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  pplx::task<etcd::Response> response_task = etcd.get("/test/key1");
  // ... do something else
  etcd::Response response = response_task.get();
  std::cout << response.value().as_string();
```

The pplx library allows to do even more. You can attach continuation objects to the task if you do
not care about when the response is coming you only want to specify what to do then. This
can be achieved by calling the `then` method of the task, giving a function object parameter to
it that can be used as a callback when the response is arrived and processed. The parameter of this
callback should be either a `etcd::Response` or a `pplx::task<etcd:Response>`. You should
probably use a C++ lambda function here as a callback.

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  etcd.get("/test/key1").then([](etcd::Response response)
  {
    std::cout << response.value().as_string();
  });

  // ... your code can continue here without any delay
```

Your lambda function should have a parameter of type `etcd::Response` or
`pplx::task<etcd::Response>`. In the latter case you can get the actual `etcd::Response`
object with the `get()` function of the task. Calling get can raise exceptions so this is the way
how you can catch the errors generated by the REST interface. The `get()` call will not block in
this case since the response has been already arrived (we are inside the callback).

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  etcd.get("/test/key1").then([](pplx::task<etcd::Response> response_task)
  {
    try
    {
      etcd::Response response = response_task.get(); // can throw
      std::cout << response.value().as_string();
    }
    catch (std::exception const & ex)
    {
      std::cerr << ex.what();
    }
  });

  // ... your code can continue here without any delay
```

## etcd operations

### Multiple endpoints

Connecting to multiple endpoints is supported:

```c++
  // multiple endpoints are separated by comma
  etcd::Client etcd("http://a.com:2379,http://b.com:2379,http://c.com:2379");

  // or, separated semicolon
  etcd::Client etcd("http://a.com:2379;http://b.com:2379;http://c.com:2379");
```

Behind the screen, gRPC's load balancer is used and the round-robin strategy will
be used by default.

### Etcd authentication

#### v3 authentication

Etcd [v3 authentication](https://etcd.io/docs/v3.4.0/learning/design-auth-v3/) has been
supported. The `Client::Client` could accept a `username` and `password` as arguments and handle
the authentication properly.

```c++
  etcd::Client etcd("http://127.0.0.1:2379", "root", "root");
```

Or the etcd client can be constructed explicitly:

```c++
  etcd::Client *etcd = etcd::Client::WithUser(
                    "http://127.0.0.1:2379", "root", "root");
```

The default authentication token will be expired every 5 minutes (300 seconds), which is controlled by
the `--auth-token-ttl` flag of etcd. When constructing a etcd client, a customized TTL value is allow:

```c++
  etcd::Client etcd("http://127.0.0.1:2379", "root", "root", 300);
```

Enabling v3 authentication requires a bit more work for older versions etcd (etcd 3.2.x and etcd 3.3.x).
First you need to set the `ETCDCTL_API=3`, then

+ add a user, and type the password:

```bash
printf 'root\nroot\n' | /usr/local/bin/etcdctl user add root
```

+ enabling authentication:

```bash
/usr/local/bin/etcdctl auth enable
```

+ disable authentication:

```bash
/usr/local/bin/etcdctl --user="root:root" auth disable
```

#### transport security

Etcd [transport security](https://etcd.io/docs/v3.4.0/op-guide/security/) and certificate based
authentication have been supported as well. The `Client::Client` could accept arguments `ca` ,
`cert` and `privkey` for CA cert, cert and private key files for the SSL/TLS transport and authentication.
Note that the later arguments `cert` and `privkey` could be empty strings or omitted if you just need
secure transport and don't enable certificate-based client authentication (using the `--client-cert-auth`
arguments when launching etcd server).

```c++
  etcd::Client etcd("https://127.0.0.1:2379",
                    "example.rootca.cert", "example.cert", "example.key",
                    "round_robin");
```

Or the etcd client can be constructed explicitly:

```c++
  etcd::Client *etcd = etcd::Client::WithSSL(
                    "https://127.0.0.1:2379",
                    "example.rootca.cert", "example.cert", "example.key");
```

Using secure transport but not certificated-based client authentication:

```c++
  etcd::Client *etcd = etcd::Client::WithSSL(
                    "https://127.0.0.1:2379", "example.rootca.cert");
```

For more details about setup about security communication between etcd server and client, please
refer to [transport security](https://etcd.io/docs/v3.4.0/op-guide/security/) in etcd documentation
and [an example](https://github.com/kelseyhightower/etcd-production-setup) about setup etcd with
transport security using openssl.

We also provide a tool [`setup-ca.sh`](./security-config/setup-ca.sh) as a helper for development and testing.

#### transport security & multiple endpoints

If you want to use multiple `https://` endpoints, and you are working with self-signed certificates, you
may encountered errors like

```
error: 14: connections to all backends failing
```

That means your DNS have some problems with your DNS resolver and SSL authority, you could put a domain
name (a host name) to the `SANS` field when self-signing your certificate, e.g,

```
"sans": [
  "etcd",
  "127.0.0.1",
  "127.0.0.2",
  "127.0.0.3"
],
```

And pass a `target_name_override` arguments to `WithSSL`,

```cpp
  etcd::Client *etcd = etcd::Client::WithSSL(
                    "https://127.0.0.1:2379,https://127.0.0.2:2479",
                    "example.rootca.cert", "example.cert", "example.key", "etcd");
```

For more discussion about this feature, see also [#87](https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3/issues/87),
[grpc#20186](https://github.com/grpc/grpc/issues/20186) and [grpc#22119](https://github.com/grpc/grpc/issues/22119).

### Fine-grained gRPC channel arguments

By default the etcd-cpp-apiv3 library will set the following arguments for transport layer

+ `GRPC_ARG_MAX_SEND_MESSAGE_LENGTH` to `INT_MAX`
+ `GRPC_ARG_MAX_RECEIVE_MESSAGE_LENGTH` to `INT_MAX`

If _load balancer strategy_ is specified, the following argument will be set

+ `GRPC_ARG_LB_POLICY_NAME`

When transport security is enabled and `target_name_override` is specified when working with SSL, the
following argument will be set

+ `GRPC_SSL_TARGET_NAME_OVERRIDE_ARG`

Further, all variants of constructors for `etcd::Client` accepts an extra `grpc::ChannelArguments` argument
which can be used for fine-grained control the gRPC settings, e.g.,

```cpp
  grpc::ChannelArguments grpc_args;
  grpc_args.SetInt(GRPC_ARG_KEEPALIVE_TIME_MS, 2000);
  grpc_args.SetInt(GRPC_ARG_KEEPALIVE_TIMEOUT_MS, 6000);
  grpc_args.SetInt(GRPC_ARG_KEEPALIVE_PERMIT_WITHOUT_CALLS, 1);

  etcd::Client etcd("http://127.0.0.1:2379", grpc_args);
```

For more motivation and discussion about the above design, please refer to [issue-103](https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3/issues/103).

### gRPC timeout when waiting for responses

gRPC Timeout is long-standing missing pieces in the etcd-cpp-apiv3 library. The timeout has been
supported via a `set_grpc_timeout` interfaces on the client,

```cpp
  template <typename Rep = std::micro>
  void set_grpc_timeout(std::chrono::duration<Rep> const &timeout)
```

Any `std::chrono::duration` value can be used to set the grpc timeout, e.g.,

```cpp
  etcd.set_grpc_timeout(std::chrono::seconds(5));
```

Note that the timeout value is the "timeout" when waiting for responses upon the gRPC channel, i.e., `CompletionQueue::AsyncNext`.
It doesn't means the timeout between issuing a `.set()` method getting the `etcd::Response`, as in the async mode the such a time
duration is unpredictable and the gRPC timeout should be enough to avoid deadly waiting (e.g., waiting for a `lock()`).

### Reading a value

You can read a value with the `get()` method of the client instance. The only parameter is the
key to be read. If the read operation is successful then the value of the key can be acquired with
the `value()` method of the response. Success of the operation can be checked with the
`is_ok()` method of the response. In case of an error, the `error_code()` and
`error_message()` methods can be called for some further detail.

Please note that there can be two kind of error situations. There can be some problem with the
communication between the client and the etcd server. In this case the `get()``` method of the
response task will throw an exception as shown above. If the communication is ok but there is some
problem with the content of the actual operation, like attempting to read a non-existing key then the
response object will give you all the details. Let's see this in an example.

The Value object of the response also holds some extra information besides the string value of the
key. You can also get the index number of the creation and the last modification of this key with
the `created_index()` and the `modified_index()` methods.

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  pplx::task<etcd::Response> response_task = etcd.get("/test/key1");

  try
  {
    etcd::Response response = response_task.get(); // can throw
    if (response.is_ok())
      std::cout << "successful read, value=" << response.value().as_string();
    else
      std::cout << "operation failed, details: " << response.error_message();
  }
  catch (std::exception const & ex)
  {
    std::cerr << "communication problem, details: " << ex.what();
  }
```

### Modifying a value

Setting the value of a key can be done with the `set()` method of the client. You simply pass
the key and the value as string parameters and you are done. The newly set value object can be asked
from the response object exactly the same way as in case of the reading (with the `value()`
method). This way you can check for example the index value of your modification. You can also check
what was the previous value that this operation was overwritten. You can do that with the
`prev_value()` method of the response object.

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  pplx::task<etcd::Response> response_task = etcd.set("/test/key1", "42");

  try
  {
    etcd::Response response = response_task.get();
    if (response.is_ok())
      std::cout << "The new value is successfully set, previous value was "
                << response.prev_value().as_string();
    else
      std::cout << "operation failed, details: " << response.error_message();
  }
  catch (std::ecxeption const & ex)
  {
    std::cerr << "communication problem, details: " << ex.what();
  }
```

The set method creates a new leaf node if it weren't exists already or modifies an existing one.
There are a couple of other modification methods that are executing the write operation only upon
some specific conditions.

* `add(key, value)` creates a new value if it's key does not exists and returns a "Key
  already exists" error otherwise (error code `ERROR_KEY_ALREADY_EXISTS`)
* `modify(key, value)` modifies an already existing value or returns a "Key not found" error
  otherwise (error code `KEY_NOT_FOUND`)
* `modify_if(key, value, old_value)` modifies an already existing value but only if the previous
  value equals with old_value. If the values does not match returns with "Compare failed" error
  (code `ERROR_COMPARE_FAILED`)
* `modify_if(key, value, old_index)` modifies an already existing value but only if the index of
  the previous value equals with old_index. If the indices does not match returns with "Compare
  failed" error (code `ERROR_COMPARE_FAILED`)

### Deleting a value

Values can be deleted with the `rm` method passing the key to be deleted as a parameter. The key
should point to an existing value. There are conditional variations for deletion too.

* `rm_if(key, value, old_value)` deletes an already existing value but only if the previous
  value equals with old_value. If the values does not match returns with "Compare failed" error
  (code `ERROR_COMPARE_FAILED`)
* `rm_if(key, value, old_index)` deletes an already existing value but only if the index of
  the previous value equals with old_index. If the indices does not match returns with "Compare
  failed" error (code `ERROR_COMPARE_FAILED`)

### Handling directory nodes

Directory nodes are not supported anymore in etcdv3. However, ls and rmdir will list/delete
keys defined by the prefix. mkdir method is removed since etcdv3 treats everything as keys.

1. Creating a directory:

   Creating a directory is not supported anymore in etcdv3 cpp client. Users should remove the
   API from their code.

2. Listing a directory:

  Listing directory in etcd3 cpp client will return all keys that matched the given prefix
  recursively.

  ```c++
    etcd.set("/test/key1", "value1").wait();
    etcd.set("/test/key2", "value2").wait();
    etcd.set("/test/key3", "value3").wait();
    etcd.set("/test/subdir/foo", "foo").wait();

    etcd::Response resp = etcd.ls("/test/new_dir").get();
  ```

  ```resp.key()``` will have the following values:

  ```
  /test/key1
  /test/key2
  /test/key3
  /test/subdir/foo
  ```

  Note: Regarding the returned keys when listing a directory:

  + In etcdv3 cpp client, resp.key(0) will return "/test/new_dir/key1" since everything is
    treated as keys in etcdv3.
  + While in etcdv2 cpp client it will return "key1" and "/test/new_dir" directory should
    be created first before you can set "key1".

  When you list a directory the response object's `keys()` and `values()` methods gives
  you a vector of key names and values. The `value()` method with an integer parameter also
  returns with the i-th element of the values vector, so `response.values()[i] == response.value(i)`.

  ```c++
    etcd::Client etcd("http://127.0.0.1:2379");
    etcd::Response resp = etcd.ls("/test/new_dir").get();
    for (int i = 0; i < resp.keys().size(); ++i)
    {
      std::cout << resp.keys(i);
      std::cout << " = " << resp.value(i).as_string() << std::endl;
    }
  ```

3. Removing directory:

If you want the delete recursively then you have to pass a second `true` parameter
to rmdir and supply a key. This key will be treated as a prefix. All keys that match the
prefix will be deleted. All deleted keys will be placed in `response.values()` and
`response.keys()`. This parameter defaults to `false`.

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  etcd.set("/test/key1", "foo");
  etcd.set("/test/key2", "bar");
  etcd.set("/test/key3", "foo_bar");
  etcd::Response resp = etcd.rmdir("/test", true).get();
  for (int i = 0; i < resp.keys().size(); ++i)
  {
    std::cout << resp.keys(i);
    std::cout << " = " << resp.value(i).as_string() << std::endl;
  }
```

However, if recursive parameter is false, functionality will be the same as just deleting a key.
The key supplied will NOT be treated as a prefix and will be treated as a normal key name.

### Lock

Etcd lock has been supported as follows:

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  etcd.lock("/test/lock");
```

It will create a lease and a keep-alive job behind the screen, the lease will be revoked until
the lock is unlocked.

Users can also feed their own lease directory for lock:

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  etcd.lock_with_lease("/test/lock", lease_id);
```

### Watching for changes

Watching for a change is possible with the `watch()` operation of the client. The watch method
simply does not deliver a response object until the watched value changes in any way (modified or
deleted). When a change happens the returned result object will be the same as the result object of
the modification operation. So if the change is triggered by a value change, then
`response.action()` will return "set", `response.value()` will hold the new
value and `response.prev_value()` will contain the previous value. In case of a delete
`response.action()` will return "delete", `response.value()` will be empty and should not be
called at all and `response.prev_value()` will contain the deleted value.

As mentioned in the section "handling directory nodes", directory nodes are not supported anymore
in etcdv3.

However it is still possible to watch a whole "directory subtree", or more specifically a set of
keys that match the prefix, for changes with passing `true` to the second `recursive`
parameter of `watch` (this parameter defaults to `false` if omitted). In this case the
modified value object's `key()` method can be handy to determine what key is actually changed.
Since this can be a long lasting operation you have to be prepared that is terminated by an
exception and you have to restart the watch operation.

The watch also accepts an index parameter that specifies what is the first change we are interested
about. Since etcd stores the last couple of modifications with this feature you can ensure that your
client does not miss a single change.

Here is an example how you can watch continuously for changes of one specific key.

```c++
void watch_for_changes()
{
  etcd.watch("/nodes", index + 1, true).then([this](pplx::task<etcd::Response> resp_task)
  {
    try
    {
      etcd::Response resp = resp_task.get();
      index = resp.index();
      std::cout << resp.action() << " " << resp.value().as_string() << std::endl;
    }
    catch(...) {}
    watch_for_changes();
  });
}
```

At first glance it seems that `watch_for_changes()` calls itself on every value change but in
fact it just sends the asynchronous request, sets up a callback for the response and then returns. The
callback is executed by some thread from the pplx library's thread pool and the callback (in this
case a small lambda function actually) will call `watch_for_changes()` again from there.

#### Watcher Class

Users can watch a key indefinitely or until user cancels the watch. This can be done by
instantiating a Watcher class. The supplied callback function in Watcher class will be
called every time there is an event for the specified key. Watch stream will be cancelled
either by user implicitly calling `Cancel()` or when watcher class is destroyed.

```c++
  etcd::Watcher watcher("http://127.0.0.1:2379", "/test", printResponse);
  etcd.set("/test/key", "42"); /* print response will be called */
  etcd.set("/test/key", "43"); /* print response will be called */
  watcher.Cancel();
  etcd.set("/test/key", "43"); /* print response will NOT be called,
                                  since watch is already cancelled */
```

#### Watcher re-connection

A watcher will be disconnected from etcd server in some cases, for some examples, the etcd
server is restarted, or the network is temporarily unavailable. It is users' responsibility
to decide if a watcher should re-connect to the etcd server.

Here is an example how users can make a watcher re-connect to server after disconnected.

```c++
// wait the client ready
void wait_for_connection(etcd::Client &client) {
  // wait until the client connects to etcd server 
  while (!client.head().get().is_ok()) {
    sleep(1);
  }
}

// a loop for initialized a watcher with auto-restart capability
void initialize_watcher(const std::string& endpoints,
                        const std::string& prefix,
                        std::function<void(etcd::Response)> callback,
                        std::shared_ptr<etcd::Watcher>& watcher) {
  etcd::Client client(endpoints);
  wait_for_connection(client);

  // Check if the failed one has been cancelled first
  if (watcher && watcher->Cancelled()) {
    std::cout << "watcher's reconnect loop been cancelled" << std::endl;
    return;
  }
  watcher.reset(new etcd::Watcher(client, prefix, callback, true));

  // Note that lambda requires `mutable`qualifier.
  watcher->Wait([endpoints, prefix, callback,
    /* By reference for renewing */ &watcher](bool cancelled) mutable {
    if (cancelled) {
      std::cout << "watcher's reconnect loop stopped as been cancelled" << std::endl;
      return;
    }
    initialize_watcher(endpoints, prefix, callback, watcher);
  });
}
```

The functionalities can be used as

```c++
std::string endpoints = "http://127.0.0.1:2379";  
std::function<void(Response)> callback = printResponse;
const std::string prefix = "/test/key"; 

// the watcher initialized in this way will auto re-connect to etcd
std::shared_ptr<etcd::Watcher> watcher;
initialize_watcher(endpoints, prefix, callback, watcher);
```

For a complete runnable example, see also [./tst/RewatchTest.cpp](./tst/RewatchTest.cpp).

### Requesting for lease

Users can request for lease which is governed by a time-to-live(TTL) value given by the user.
Moreover, user can attached the lease to a key(s) by indicating the lease id in `add()`,
`set()`, `modify()` and `modify_if()`. Also the ttl will that was granted by etcd
server will be indicated in `ttl()`.

```c++
  etcd::Client etcd("http://127.0.0.1:2379");
  etcd::Response resp = etcd.leasegrant(60).get();
  etcd.set("/test/key2", "bar", resp.value().lease());
  std::cout << "ttl" << resp.value().ttl();
```

The lease can be revoked by

```c++
  etcd.leaserevoke(resp.value().lease());
```

A lease can also be attached with a `KeepAlive` object at the creation time,

```c++
  std::shared_ptr<etcd::KeepAlive> keepalive = etcd.leasekeepalive(60).get();
  std::cout << "lease id: " << keepalive->Lease();
```

The remaining time-to-live of a lease can be inspected by

```c++
  etcd::Response resp2 = etcd.leasetimetolive(resp.value().lease()).get();
  std::cout << "ttl" << resp.value().ttl();
```

#### Keep alive

Keep alive for leases is implemented using a separate class `KeepAlive`, which can be used as:

```c++
  etcd::KeepAlive keepalive(etcd, ttl, lease_id);
```

It will perform a period keep-alive action before it is cancelled explicitly, or destructed implicitly.

`KeepAlive` may fails (e.g., when the etcd server stopped unexpectedly), the constructor of `KeepAlive`
could accept a handler of type `std::function<std::exception_ptr>` and the handler will be invoked
when exception occurs during keeping it alive.

Note that the handler will invoked in a separated thread, not the thread where the `KeepAlive` object
is constructed.

```c++
  std::function<void (std::exception_ptr)> handler = [](std::exception_ptr eptr) {
    try {
        if (eptr) {
            std::rethrow_exception(eptr);
        }
    } catch(const std::runtime_error& e) {
        std::cerr << "Connection failure \"" << e.what() << "\"\n";
    } catch(const std::out_of_range& e) {
        std::cerr << "Lease expiry \"" << e.what() << "\"\n";
    }
  };
  etcd::KeepAlive keepalive(etcd, handler, ttl, lease_id);
```

Without handler, the internal state can be checked via `KeepAlive::Check()` and it will rethrow
the async exception when there are errors during keeping the lease alive.

### Election API

Etcd v3's [election APIs](https://github.com/etcd-io/etcd/blob/main/server/etcdserver/api/v3election/v3electionpb/v3election.proto)
are supported via the following interfaces,

```c++
pplx::task<Response> campaign(std::string const &name, int64_t lease_id,
                              std::string const &value);

pplx::task<Response> proclaim(std::string const &name, int64_t lease_id,
                              std::string const &key, int64_t revision,
                              std::string const &value);

pplx::task<Response> leader(std::string const &name);

std::unique_ptr<Observer> observe(std::string const &name,
                                  std::function<void(Response)> callback,
                                  const bool once = false);

pplx::task<Response> resign(std::string const &name, int64_t lease_id,
                            std::string const &key, int64_t revision);
```

for more details, please refer to [etcd/Client.hpp](./etcd/Client.hpp).

### TODO

1. Cancellation of asynchronous calls(except for watch)

## License

This project is licensed under the BSD-3-Clause license - see the [LICENSE](https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3/blob/master/LICENSE.txt).
