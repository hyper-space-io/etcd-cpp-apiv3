etcd-cpp-api is a C++ API for [etcd](ssh://git@bud-git01.emea.nsn-net.net/etcd-cpp-apiv3.git)

## Requirements

   * [C++ REST SDK](http://casablanca.codeplex.com/)
   * Boost libraries
   * [Catch](https://github.com/philsquared/Catch) for testing 
   * protobuf (https://github.com/google/protobuf/blob/master/src/README.md)
   * grpc (https://github.com/grpc/grpc/blob/release-0_14/INSTALL.md)
   
## Compatible etcd version
Use https://github.com/coreos/etcd/releases/tag/v3.0.0 onwards.

## Compatible etcd version
While developing the etcd-cpp-api for etcd version 3, we found a bug in etcd and was
eventually fixed in master branch(see: https://github.com/coreos/etcd/issues/5504#event-684957506).
This means that the etcd to be used with this etcd cpp client should be build from latest sources
in etcd master branch.
See etcd documentation on how to build etcd from source:
https://github.com/coreos/etcd/blob/master/Documentation/dl_build.md

## Updates from etcdv2 cpp client to etcdv3 cpp client
See "handling directory nodes" section

## compiling .proto
Proto files are stored in /proto. The proto files defined the interface of etcdv3.
You can compile it like this(if you are running this command inside /proto folder)
$ protoc -I . --grpc_out=. --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` ./rpc.proto
$ protoc -I . --cpp_out=. ./*.proto

Protofiles for etcdv3 can be found here:
https://github.com/coreos/etcd/tree/master/auth/authpb
https://github.com/coreos/etcd/tree/master/etcdserver/etcdserverpb
https://github.com/coreos/etcd/tree/master/mvcc/mvccpb

## generic notes

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
  etcd::Response response = etcd.get("/test/key1").get();
  std::cout << response.value().as_string();
```

Methods of the etcd client object are sending the corresponding gRPC requests and are returning
immediatelly with a ```pplx::task``` object. The task object is responsible for handling the
reception of the HTTP response as well as parsing the gRPC of the response. All of this is done
asynchronously in a background thread so you can continue your code to do other operations while the
current etcd operation is executing in the background or you can wait for the response with the
```wait()``` or ```get()``` methods if a synchron behaviour is enough for your needs. These methods
are blocking until the HTTP response arrives or some error situation happens. ```get()``` method
also returns the ```etcd::Response``` object.

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
  pplx::task<etcd::Response> response_task = etcd.get("/test/key1").get();
  // ... do something else
  etcd::Response response = response_task.get();
  std::cout << response.value().as_string();
```

The pplx library allows to do even more. You can attach continuation ojects to the task if you do
not care about when the response is coming you only want to specify what to do then. This
can be achieved by calling the ```then``` method of the task, giving a funcion object parameter to
it that can be used as a callback when the response is arrived and processed. The parameter of this
callback should be either a ```etcd::Response``` or a ```pplx::task<etcd:Response>```. You should
probably use a C++ lambda funcion here as a callback.

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
  etcd.get("/test/key1").then([](etcd::Response response)
  {
    std::cout << response.value().as_string();
  });

  // ... your code can continue here without any delay
```

Your lambda function should have a parameter of type ```etcd::Response``` or
```pplx::task<etcd::Response>```. In the latter case you can get the actual ```etcd::Response```
object with the ```get()``` function of the task. Calling get can raise exeptions so this is the way
how you can catch the errors generated by the REST interface. The ```get()``` call will not block in
this case since the respose has been already arrived (we are inside the callback).

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
  etcd.get("/test/key1").then([](pplx::task<etcd::Response> response_task)
  {
    try
    {
      etcd::Response response = response.task.get(); // can throw
      std::cout << response.value().as_string();
    }
    catch (std::ecxeption const & ex)
    {
      std::cerr << ex.what();
    }
  });

  // ... your code can continue here without any delay
```

## etcd operations

### reading a value

You can read a value with the ```get``` method of the clinent instance. The only parameter is the
key to be read. If the read operation is successful then the value of the key can be acquired with
the ```value()``` method of the response. Success of the operation can be checked with the
```is_ok()``` method of the response. In case of an error, the ```error_code()``` and
```error_message()``` methods can be called for some further detail.

Please note that there can be two kind of error situations. There can be some problem with the
communication between the client and the etcd server. In this case the ```get()``` method of the
response task will throw an exception as shown above. If the communication is ok but there is some
problem with the content of the actual operation, like attemp to read a non-existing key then the
response object will give you all the details. Let's see this in an example.

The Value object of the response also holds some extra information besides the string value of the
key. You can also get the index number of the creation and the last modification of this key with
the ```created_index()``` and the ```modofied_index()``` methods.

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
  pplx::task<etcd::Response> response_task = etcd.get("/test/key1");

  try
  {
    etcd::Response response = response_task.get(); // can throw
    if (response.is_ok())
      std::cout << "successful read, value=" << response.value().as_string();
    else
      std::cout << "operation failed, details: " << response.error_message();
  }
  catch (std::ecxeption const & ex)
  {
    std::cerr << "communication problem, details: " << ex.what();
  }
```

### modifying a value

Setting the value of a key can be done with the ```set()``` method of the client. You simply pass
the key and the value as string parameters and you are done. The newly set value object can be asked
from the response object exactly the same way as in case of the reading (with the ```value()```
method). This way you can check for example the index value of your modification. You can also check
what was the previous value that this operation was overwritten. You can do that with the
```prev_value()``` method of the response object.

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
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

   * ```add(key, value)``` creates a new value if it's key does not exists and returns a "Key
     already exists" error otherwise (error code 105)
   * ```modify(key, value)``` modifies an already existing value or returns a "Key not found" error
     otherwise (error code 100)
   * ```modify_if(key, value, old_value)``` modifies an already existing value but only if the previous
     value equals with old_value. If the values does not match returns with "Compare failed" error
     (code 101)
   * ```modify_if(key, value, old_index)``` modifies an already existing value but only if the index of
     the previous value equals with old_index. If the indices does not match returns with "Compare
     failed" error (code 101)

### deleting a value

Values can be deleted with the ```rm``` method passing the key to be deleted as a parameter. The key
should point to an existing value. There are conditional variations for deletion too.

   * ```rm_if(key, value, old_value)``` deletes an already existing value but only if the previous
     value equals with old_value. If the values does not match returns with "Compare failed" error
     (code 101)
   * ```rm_if(key, value, old_index)``` deletes an already existing value but only if the index of
     the previous value equals with old_index. If the indices does not match returns with "Compare
     failed" error (code 101)

### handling directory nodes
Directory nodes are not supported anymore in etcdv3.

However, ls and rmdir will list/delete keys defined by the prefix. mkdir method is removed since 
etcdv3 treats everything as keys. 

1. Creating a directory:
Creating a directory is not supported anymore in etcdv3 cpp client. Users should remove the 
API from their code.

2. Listing a directory:
Listing directory in etcd3 cpp client will return all keys that matched the given prefix recursively.

```c++
  etcd.set("/test/key1", "value1").wait();
  etcd.set("/test/key2", "value2").wait();
  etcd.set("/test/key3", "value3").wait();
  etcd.set("/test/subdir/foo", "foo").wait();
  
  etcd::Response resp = etcd.ls("/test/new_dir").get();
```
resp.key() will have the following values:
/test/key1 
/test/key2 
/test/key3
/test/subdir/foo


Note: Regarding the returned keys when listing a directory:
In etcdv3 cpp client, resp.key(0) will return "/test/new_dir/key1" since everything is treated as keys in etcdv3.
While in etcdv2 cpp client it will return "key1" and "/test/new_dir" directory should be created first before you can set "key1".

When you list a directory the response object's ```keys()``` and ```values()``` methods gives you a
vector of key names and values. The ```value()``` method with an integer parameter also
returns with the i-th element of the values vector, so ```response.values()[i] ==
response.value(i)```. 

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
  etcd::Response resp = etcd.ls("/test/new_dir").get();
  for (int i = 0; i < resp.keys().size(); ++i)
  {
    std::cout << resp.keys(i);
    if (resp.value(i).is_dir())
      std::cout << "/" << std::endl;
    else
      std::cout << " = " << resp.value(i).as_string() << std::endl;
  }
```

3. Removing directory:
If you want the delete recursively then you have to pass a second ```true``` parameter 
to rmdir and supply a key. This key will be treated as a prefix. All keys that match the prefix will
be deleted. This parameter defaults to ```false```.

```c++
  etcd::Client etcd("http://127.0.0.1:4001");
  etcd.rmdir("/test", true).get();
```
However, if recursive parameter is false, functionality will be the same as just deleting a key.
The key supplied will NOT be treated as a prefix and will be treated as a normal key name.

### watching for changes

Watching for a change is possible with the ```watch()``` operation of the client. The watch method
simply does not deliver a response object until the watched value changes in any way (modified or
deleted). When a change happens the returned result object will be the same as the result object of
the modification operation. So if the change is triggered by a value change, then
```response.action()``` will return "set", ```response.value()``` will hold the new
value and ```response.prev_value()``` will contain the previous value. In case of a delete
```response.action()``` will return "delete", ```response.value()``` will be empty and should not be
called at all and ```response.prev_value()``` will contain the deleted value.

As mentioned in the section "handling directory nodes", directory nodes are not supported anymore in etcdv3.
However it is still possible to watch a whole "directory subtree", or more specifically a set of keys that match the 
prefix, for changes with passing ```true``` to the second ```recursive``` parameter of ```watch``` 
(this parameter defaults to ```false``` if omitted). In this case the modified value object's ```key()``` method can be 
handy to determine what key is actually changed. Since this can be a long lasting operation you have to be prepared that is
terminated by an exception and you have to restart the watch operation.

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

At first glance it seems that ```watch_for_changes()``` calls itself on every value change but in
fact it just sends the asynchron request, sets up a callback for the response and then returns.  The
callback is executed by some thread from the pplx library's thread pool and the callback (in this
case a small lambda function actually) will call ```watch_for_changes``` again from there.

Note: etcdv3 watch functionality uses a stream for both request and response. This means that clients can 
watch a key(s) as long as it will not terminate the stream. However, as stated above existing watch() will
return once an event is received for the watch request(a httpv1 limitation) and watch for the key(s) will
cancelled. Current set of API does not yet support watching a key(s) for indefinite periods. This functionality
can be added in the future releases of etcd-cpp-clientv3.