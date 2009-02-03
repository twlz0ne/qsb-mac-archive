//
//  HGSPythonAction.m
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

#import "HGSPythonAction.h"
#import "HGSLog.h"
#import "HGSBundle.h"

static const char *const kDoesActionApplyTo = "DoesActionApplyTo";
static const char *const kPerformAction = "PerformAction";

@implementation HGSPythonAction

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
      HGSLogDebug(@"Can't instantiate python action. "
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
      HGSLogDebug(@"could instantiate Python class %@.\n%@", className, error);
      [self release];
      return nil;
    }
    performAction_ = PyString_FromString(kPerformAction);
    if (!performAction_) {
      NSString *error = [HGSPython lastErrorString];
      HGSLogDebug(@"could not create Python string %s.\n%@", 
                  kPerformAction, error);
      [self release];
      return nil;
    }
    doesActionApplyTo_ = PyString_FromString(kDoesActionApplyTo);
    if (!doesActionApplyTo_) {
      NSString *error = [HGSPython lastErrorString];
      HGSLogDebug(@"could not create Python string %s.\n%@", 
                  kDoesActionApplyTo, error);
      [self release];
      return nil;
    }
  }

  return self;
}

- (void)dealloc {
  if (performAction_ || doesActionApplyTo_ || instance_ || module_) {
    PythonStackLock gilLock;
    if (performAction_) {
      Py_DECREF(performAction_);
    }
    if (doesActionApplyTo_) {
      Py_DECREF(doesActionApplyTo_);
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

- (NSDictionary*)performActionWithInfo:(NSDictionary*)info {
  HGSObject *primary = [info valueForKey:kHGSActionPrimaryObjectKey];
  HGSObject *indirect = [info valueForKey:kHGSActionIndirectObjectKey];
  
  if (instance_ && primary) {
    PythonStackLock gilLock;
    PyObject *pyPrimary = [[HGSPython sharedPython] objectForResult:primary];
    PyObject *pyIndirect = nil;
    if (indirect) {
      pyIndirect = [[HGSPython sharedPython] objectForResult:indirect];
    }
    if (pyPrimary) {
      // TODO(hawk): add pivot object to the call
      PyObject *pythonResult =
        PyObject_CallMethodObjArgs(instance_,
                                   performAction_,
                                   pyPrimary,
                                   nil);
      if (pythonResult) {
        Py_DECREF(pythonResult);
      }
      Py_DECREF(pyPrimary);
    }
    if (pyIndirect) {
      Py_DECREF(pyIndirect);
    }
  }
  
  return [NSDictionary dictionary];
}

- (NSSet*)directObjectTypes {
  // TODO(hawk): update this to fetch a list of types from the plugin set like
  // the applescript actions do.
  return [NSSet setWithObject:@"*"];
}

- (BOOL)doesActionApplyTo:(HGSObject*)result {
  PythonStackLock gilLock;
  BOOL applies = NO;
  
  PyObject *pyResult = [[HGSPython sharedPython] objectForResult:result];
  if (pyResult) {
    PyObject *pyApplies =
      PyObject_CallMethodObjArgs(instance_,
                                 doesActionApplyTo_,
                                 pyResult,
                                 nil);
    if (pyApplies) {
      if (PyBool_Check(pyApplies) && pyApplies == Py_True) {
        applies = YES;
      }
      Py_DECREF(pyApplies);
    }
    Py_DECREF(pyResult);
  }
  
  return applies;
}

@end
