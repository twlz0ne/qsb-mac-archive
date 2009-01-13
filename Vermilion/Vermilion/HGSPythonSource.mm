//
//  HGSPythonSource.m
//
//  Copyright (c) 2008 Google Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
//
//    * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following disclaimer
//  in the documentation and/or other materials provided with the
//  distribution.
//    * Neither the name of Google Inc. nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "HGSPythonSource.h"
#import "HGSQuery.h"
#import "HGSLog.h"
#import "HGSIconProvider.h"
#import "HGSSearchOperation.h"
#import "HGSBundle.h"

static const char *const kPerformSearch = "PerformSearch";
static const char *const kIsValidSourceForQuery = "IsValidSourceForQuery";

@implementation HGSPythonSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSString *moduleName = [configuration objectForKey:kPythonModuleNameKey];
    NSString *className = [configuration objectForKey:kPythonClassNameKey];
    // Default module to class if it's not set specifically
    if ([moduleName length] == 0) {
      moduleName = className;
    }
    NSBundle *bundle = [configuration objectForKey:kHGSExtensionBundleKey];
    if (!bundle || !moduleName || !className) {
      HGSLogDebug(@"Can't instantiate python source. "
                  @"Missing %@ or %@ or %@ in %@", kPythonModuleNameKey,
                  kPythonClassNameKey, kHGSExtensionBundleKey, configuration);
      [self release];
      return nil;
    }
    HGSPython *pythonContext = [HGSPython sharedPython];
    NSString *resourcePath = [bundle resourcePath];
    if (resourcePath) {
      [pythonContext appendPythonPath:resourcePath];
    }
    
    PythonStackLock gilLock;
    
    module_ = [pythonContext loadModule:moduleName];
    if (!module_) {
      HGSLogDebug(@"failed to load Python module %@", moduleName);
      [self release];
      return nil;
    }
    
    // Instantiate the class
    PyObject *dict = PyModule_GetDict(module_);
    PyObject *pythonClass = PyDict_GetItemString(dict, [className UTF8String]);
    if (!pythonClass) {
      NSString *error = [HGSPython lastErrorString];
      HGSLogDebug(@"could not find Python class %@.\n%@", className, error);
      [self release];
      return nil;
    }
    if (!PyCallable_Check(pythonClass)) {
      NSString *error = [HGSPython lastErrorString];
      HGSLogDebug(@"no ctor for Python class %@.\n%@", className, error);
      [self release];
      return nil;
    }
    instance_ = PyObject_CallObject(pythonClass, NULL);
    if (!instance_) {
      NSString *error = [HGSPython lastErrorString];
      HGSLogDebug(@"could not instantiate Python class %@.\n%@", 
                  className, error);
      [self release];
      return nil;
    }
    isValidSourceForQuery_ = PyString_FromString(kIsValidSourceForQuery);
    if (!isValidSourceForQuery_) {
      NSString *error = [HGSPython lastErrorString];
      HGSLogDebug(@"could not create Python string %s.\n%@", 
                  kIsValidSourceForQuery, error);
      [self release];
      return nil;
    }
  }
  return self;
}

- (void)dealloc {
  if (isValidSourceForQuery_ || instance_ || module_) {
    PythonStackLock gilLock;
    if (isValidSourceForQuery_) {
      Py_DECREF(isValidSourceForQuery_);
    }
    if (instance_) {
      Py_DECREF(instance_);
    }
    if (module_) {
      Py_DECREF(module_);
    }
  }
  [super dealloc];
}

- (HGSSearchOperation *)searchOperationForQuery:(HGSQuery *)query{
  HGSPythonSearchOperation *op 
    = [[[HGSPythonSearchOperation alloc] initWithQuery:query 
                                                source:self] autorelease];
  return op;
}

- (NSSet *)pivotableTypes {
  // TODO(hawk): We need to let the python scripts say what types they can
  // pivot on so we can avoid sending all pivots to the sources.
  return [NSSet setWithObject:@"*"];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  PythonStackLock gilLock;
  BOOL result = YES;  
  
  PyObject *pyQuery = [[HGSPython sharedPython] objectForQuery:query
                                           withSearchOperation:nil];
    
  if (instance_ && isValidSourceForQuery_ && pyQuery) {
    PyObject *pyValid =
      PyObject_CallMethodObjArgs(instance_,
                                 isValidSourceForQuery_,
                                 pyQuery,
                                 nil);
    if (pyValid) {
      if (PyBool_Check(pyValid)) {
        result = (pyValid == Py_True);
      }
      Py_DECREF(pyValid);
    }
  }
  
  if (pyQuery) {
    Py_DECREF(pyQuery);
  }
  
  return result;
}

- (PyObject *)instance {
  return instance_;
}

@end


@implementation HGSPythonSearchOperation

- (id)initWithQuery:(HGSQuery*)query
             source:(HGSPythonSource *)source {
  self = [super initWithQuery:query];
  if (self) {
    source_ = [source retain];
  }
  return self;
}

- (void)dealloc {
  [source_ release];
  [super dealloc];
}

- (void)main {
  BOOL running = NO;
  
  if ([source_ instance]) {
    HGSQuery *hgsQuery = [self query];
    PyObject *query = [[HGSPython sharedPython] objectForQuery:hgsQuery
                                           withSearchOperation:self];
    if (query) {
      PythonStackLock gilLock;
      PyObject *performSearchString = PyString_FromString(kPerformSearch);
      if (performSearchString) {
        PyObject_CallMethodObjArgs([source_ instance],
                                   performSearchString,
                                   query,
                                   nil);
        PyObject *err = PyErr_Occurred();
        if (!err) {
          running = YES;
        } else {
          // err is a borrowed reference, do not Py_DECREF it
#if DEBUG
          PyErr_Print();
#endif
          PyErr_Clear();
        }
        Py_DECREF(performSearchString);
      } else {
        NSString *error = [HGSPython lastErrorString];
        HGSLogDebug(@"failed to create Python string for "
                    @"'performSearchString'.\n%@", error);
      }
      Py_DECREF(query);
    } else {
      HGSLogDebug(@"could not create Python query for '%@'", 
                  [hgsQuery rawQueryString]);
    }
  }
  
  if (!running) {
    [self finishQuery];
  }
}

- (BOOL)isConcurrent {
  return YES;
}

- (HGSPythonSource *)source {
  return source_;
}

@end
