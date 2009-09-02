//
//  HGSPython.m
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

#import "HGSPython.h"
#import "HGSResult.h"
#import "HGSQuery.h"
#import "HGSLog.h"
#import "HGSSearchTermScorer.h"
#import "HGSAction.h"
#import "HGSBundle.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSPythonSource.h"
#import "HGSTokenizer.h"    
#import "GTMObjectSingleton.h"
#import <Python/structmember.h>

const NSString *kHGSPythonPrivateValuesKey = @"kHGSPythonPrivateValuesKey";
const NSString *kHGSPythonThreadBundleKey = @"HGSPythonThreadBundleKey";

NSString *const kPythonModuleNameKey = @"HGSPythonModule";
NSString *const kPythonClassNameKey = @"HGSPythonClass";

static const char *kAddSysPathFuncName = "AddPathToSysPath";
static const char *kQueryClassName = "Query";
static const char *kPythonResultIdentifierKey = "IDENTIFIER";
static const char *kPythonResultDisplayNameKey = "DISPLAY_NAME";
static const char *kPythonResultSnippetKey = "SNIPPET";
static const char *kPythonResultImageKey = "IMAGE";
static const char *kPythonResultDefaultActionKey = "DEFAULT_ACTION";
static const char *kPythonResultTypeKey = "TYPE";
static const char *kHGSPythonNormalizedQueryMemberName = "normalized_query";
static const char *kHGSPythonRawQueryMemberName = "raw_query";
static const char *kHGSPythonPivotObjectMemberName = "pivot_object";

typedef struct {
  PyObject_HEAD
  PyObject  *rawQuery_;    // string
  PyObject  *normalizedQuery_; // string
  PyObject  *pivotObject_; // dictionary
  HGSPythonSearchOperation  *operation_;
} Query;

static PyObject *QueryNew(PyTypeObject *type, PyObject *args, PyObject *kwds);
static void QueryDealloc(Query *self);
static int QueryInit(Query *self, PyObject *args, PyObject *kwds);
static PyObject *QueryGetAttr(Query *self, char *name);
static int QuerySetAttr(Query *self, char *name, PyObject *value);
static PyObject *QuerySetResults(Query *self, PyObject *args);
static PyObject *QueryFinish(Query *self, PyObject *unused);
static PyObject *LocalizeString(PyObject *self, PyObject *args);

static PyMethodDef QueryMethods[] = {
  {
    "SetResults", (PyCFunction)QuerySetResults, METH_VARARGS,
    "Append a set of results to the query."
  },
  {
    "Finish", (PyCFunction)QueryFinish, METH_NOARGS,
    "Indicate that query processing has completed."
  },
  { NULL, NULL, 0, NULL  }
};

static PyMemberDef QueryMembers[] = {
  { const_cast<char*>(kHGSPythonNormalizedQueryMemberName), 
    T_OBJECT_EX, offsetof(Query, normalizedQuery_), 0,
    const_cast<char*>("The raw query broken into tokens delimited by spaces. "
                      "It has also been normalized to having no diacriticals "
                      "or excess punctuation, and has been converted to "
                      "lowercase.")},
  { const_cast<char*>(kHGSPythonRawQueryMemberName), 
    T_OBJECT_EX, offsetof(Query, rawQuery_), 0,
    const_cast<char*>("The unprocessed query entered by the user.") },
  { const_cast<char*>(kHGSPythonPivotObjectMemberName),
    T_OBJECT_EX, offsetof(Query, pivotObject_), 0,
    const_cast<char*>("If present, the original search result from which this "
                      "query is pivoting.") },
  { NULL, 0, 0,0, NULL }
};

static PyTypeObject QueryType = {
  PyObject_HEAD_INIT(NULL)
  0,                            // ob_size
  "Vermilion.Query",           // tp_name
  sizeof(Query),                // tp_basicsize
  0,                            // tp_itemsize
  (destructor)QueryDealloc,     // tp_dealloc
  0,                            // tp_print
  (getattrfunc)QueryGetAttr,    // tp_getattr
  (setattrfunc)QuerySetAttr,    // tp_setattr
  0,                            // tp_compare
  0,                            // tp_repr
  0,                            // tp_as_number
  0,                            // tp_as_sequence
  0,                            // tp_as_mapping
  0,                            // tp_hash
  0,                            // tp_call
  0,                            // tp_str
  0,                            // tp_getattro
  0,                            // tp_setattro
  0,                            // tp_as_buffer
  Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE, // tp_flags
  "Query objects",              // tp_doc
  0,                            // tp_traverse
  0,                            // tp_clear
  0,                            // tp_richcompare
  0,                            // tp_weaklistoffset
  0,                            // tp_iter
  0,                            // tp_iternext
  QueryMethods,                 // tp_methods
  QueryMembers,                 // tp_members
  0,                            // tp_getset
  0,                            // tp_base
  0,                            // tp_dict
  0,                            // tp_descr_get
  0,                            // tp_descr_set
  0,                            // tp_dictoffset
  (initproc)QueryInit,          // tp_init
  0,                            // tp_alloc
  QueryNew,                     // tp_new
  0,                            // tp_free
  0,                            // tp_is_gc
  0,                            // tp_bases
  0,                            // tp_mro
  0,                            // tp_cache
  0,                            // tp_subclasses
  0,                            // tp_weaklist
  0,                            // tp_del
};

static PyMethodDef LocalizeMethods[] = {
  { "String", LocalizeString, METH_VARARGS,
    "Returns the localized version of a string."
  },
  { NULL, NULL, 0, NULL }
};

// A simple wrapper for PyObject which allows it to be used in
// Objective-C containers
@implementation HGSPythonObject

+ (HGSPythonObject *)pythonObjectWithObject:(PyObject *)object {
  return [[[HGSPythonObject alloc] initWithObject:object] autorelease];
}

- (id)initWithObject:(PyObject *)object {
  self = [super init];
  if (self) {
    PythonStackLock gilLock;
    object_ = object;
    Py_INCREF(object_);
  }
  return self;
}

- (void)dealloc {
  if (object_) {
    PythonStackLock gilLock;
    Py_DECREF(object_);
  }
  [super dealloc];
}

- (PyObject *)object {
  return object_;
}

@end // HGSPythonObject

@implementation HGSPython

GTMOBJECT_SINGLETON_BOILERPLATE(HGSPython, sharedPython);

- (id)init {
  if ((self = [super init])) {
    // Add our bundle Resources directory to the Python path so
    // that our support scripts can be located by the interpreter
    NSBundle *bundle = HGSGetPluginBundle();
    NSString *resourcePath = [bundle resourcePath];
    NSString *newPythonPath;
    char *oldPythonPath = getenv("PYTHONPATH");
    if (oldPythonPath) {
      newPythonPath = [NSString stringWithFormat:@"%s:%@", oldPythonPath,
                       resourcePath];
    } else {
      newPythonPath = resourcePath;
    }
    setenv("PYTHONPATH", [newPythonPath UTF8String], 1);
    
    char pythonPath[] = "/usr/bin/python";
    // Initialize the interpreter
    Py_SetProgramName(pythonPath);
    Py_InitializeEx(0);
    PyEval_InitThreads();
    Py_InitModule("VermilionLocalize", LocalizeMethods);
    
    // Release the global intepreter lock (which is automatically
    // locked by PyEval_InitThreads())
    PyGILState_Release(PyGILState_UNLOCKED);
    
    // Load our utility module
    vermilionModule_ = [self loadModule:@"Vermilion"];
    if (vermilionModule_) {
      // Add the constants used as keys in result dictionaries
      PyModule_AddStringConstant(vermilionModule_, kPythonResultIdentifierKey,
                                 [kHGSObjectAttributeURIKey UTF8String]);
      PyModule_AddStringConstant(vermilionModule_, kPythonResultDisplayNameKey,
                                 [kHGSObjectAttributeNameKey UTF8String]);
      PyModule_AddStringConstant(vermilionModule_, kPythonResultSnippetKey,
                                 [kHGSObjectAttributeSnippetKey UTF8String]);
      PyModule_AddStringConstant(vermilionModule_, kPythonResultImageKey,
                                 [kHGSObjectAttributeIconPreviewFileKey UTF8String]);
      PyModule_AddStringConstant(vermilionModule_, kPythonResultDefaultActionKey,
                                 [kHGSObjectAttributeDefaultActionKey UTF8String]);
      PyModule_AddStringConstant(vermilionModule_, kPythonResultTypeKey,
                                 [kHGSObjectAttributeTypeKey UTF8String]);
      // Add our implemented-in-C Query class
      if (PyType_Ready(&QueryType) >= 0) {
        Py_INCREF(&QueryType);
        PyModule_AddObject(vermilionModule_, kQueryClassName,
                           (PyObject *)&QueryType);
      }
    }
  }
  return self;
}

- (void)dealloc {
  if (vermilionModule_) {
    Py_DECREF(vermilionModule_);
  }
  [super dealloc];
}

- (PyObject *)objectForResult:(HGSResult *)result {
  PyObject *dict = PyDict_New();
  if (dict) {
    // Identifier
    NSURL *url = [result url];
    NSString *value = [url absoluteString];
    PyObject *pyValue;
    if (value && (pyValue = PyString_FromString([value UTF8String]))) {
      PyDict_SetItemString(dict, 
                           [kHGSObjectAttributeURIKey UTF8String], pyValue);
      Py_DECREF(pyValue);
    }
    
    // Display Name
    value = [result valueForKey:kHGSObjectAttributeNameKey];
    if (value && (pyValue = PyString_FromString([value UTF8String]))) {
      PyDict_SetItemString(dict, 
                           [kHGSObjectAttributeNameKey UTF8String], pyValue);
      Py_DECREF(pyValue);
    }
    
    // Type
    value = [result valueForKey:kHGSObjectAttributeTypeKey];
    if (value && (pyValue = PyString_FromString([value UTF8String]))) {
      PyDict_SetItemString(dict,
                           [kHGSObjectAttributeTypeKey UTF8String], pyValue);
      Py_DECREF(pyValue);
    }
    
    // Snippet
    value = [result valueForKey:kHGSObjectAttributeSnippetKey];
    if (value && (pyValue = PyString_FromString([value UTF8String]))) {
      PyDict_SetItemString(dict, 
                           [kHGSObjectAttributeSnippetKey UTF8String], pyValue);
      Py_DECREF(pyValue);
    }
    
    // Icon URL
    url = [result valueForKey:kHGSObjectAttributeIconPreviewFileKey];
    value = [url absoluteString];
    if (value && (pyValue = PyString_FromString([value UTF8String]))) {
      PyDict_SetItemString(dict, 
                           [kHGSObjectAttributeIconPreviewFileKey UTF8String], 
                           pyValue);
      Py_DECREF(pyValue);
    }
    
    // Private values generated by Python search sources
    NSDictionary *privateValues 
      = [result valueForKey:kHGSPythonPrivateValuesKey];
    for (NSString *key in [privateValues allKeys]) {
      HGSPythonObject *wrapper = [privateValues valueForKey:key];
      pyValue = [wrapper object];
      if (pyValue) {
        PyDict_SetItemString(dict, [key UTF8String], pyValue);
      }
    }
  }
  return dict;
}

- (PyObject *)tupleForResults:(HGSResultArray *)array {
  PyObject *pyTuple = NULL;
  NSUInteger count = [array count];
  if (count) {
    pyTuple = PyTuple_New(count);
    if (pyTuple) {
      for (NSUInteger i = 0; i < count; ++i) {
        HGSResult *result = [array objectAtIndex:i];
        PyObject *pyObj = [self objectForResult:result];
        if (pyObj) {
          PyTuple_SetItem(pyTuple, i, pyObj);
        }
      }
    }
  }
  return pyTuple;
}

- (PyObject *)objectForQuery:(HGSQuery *)query
         withSearchOperation:(HGSSearchOperation *)operation {
  PyObject *result = nil;  
  if (vermilionModule_) {
    PythonStackLock gilLock;
    PyObject *moduleDict = PyModule_GetDict(vermilionModule_);
    if (moduleDict) {
      PyObject *func = PyDict_GetItemString(moduleDict, "Query");
      if (func) {
        PyObject *args = PyTuple_New(3);
        if (args) {
          // Create the normalized_query argument (ref stolen by PyTuple_SetItem
          const char *utf8 = [[query normalizedQueryString] UTF8String];
          if (utf8) {
            PyTuple_SetItem(args, 0, PyString_FromString(utf8));
          } else {
            PyTuple_SetItem(args, 0, PyString_FromString(""));
          }
          
          // Create the raw_query argument (ref stolen by PyTuple_SetItem()
          utf8 = [[query rawQueryString] UTF8String];
          if (utf8) {
            PyTuple_SetItem(args, 1, PyString_FromString(utf8));
          } else {
            PyTuple_SetItem(args, 1, PyString_FromString(""));
          }
          
          // Create the pivot_object argument
          HGSResult *pivotObject = [query pivotObject];
          PyObject *pyPivotObject = Py_None;
          if (pivotObject) {
            pyPivotObject = [self objectForResult:pivotObject];
          }
          // Steals the pyPivotObject ref
          PyTuple_SetItem(args, 2, pyPivotObject);
        
          result = PyObject_CallObject(func, args);
        
          if (result) {
            Query *pyquery = (Query *)result;
            pyquery->operation_ = [operation retain];
          }
          
        } else {
          NSString *error = [HGSPython lastErrorString];
          HGSLogDebug(@"could not allocate tuple in objectForQuery:.\n%@",
                      error);
        }
      } else {
        NSString *error = [HGSPython lastErrorString];
        HGSLogDebug(@"could locate Query object in objectForQuery:.\n%@",
                    error);

      }
    } else {
      NSString *error = [HGSPython lastErrorString];
      HGSLogDebug(@"could not get module dictionary in objectForQuery:.\n%@",
                  error);

    }
  } else {
    NSString *error = [HGSPython lastErrorString];
    HGSLogDebug(@"nil vermilionModule_ in objectForQuery:.\n%@",
                error);

  }
  return result;
}

- (PyObject *)loadModule:(NSString *)moduleName {
  PythonStackLock gilLock;
  PyObject *pythonModuleName, *module = nil;
  pythonModuleName = PyString_FromString([moduleName UTF8String]);
  if (!pythonModuleName) {
    NSString *error = [HGSPython lastErrorString];
    HGSLogDebug(@"could not create Python string for %@\n%@", 
                moduleName, error);
    return nil;
  }
  module = PyImport_Import(pythonModuleName);
  if (!module) {
    NSString *error = [HGSPython lastErrorString];
    HGSLogDebug(@"could not load Python module %@\n%@", moduleName, error);
  }
  Py_DECREF(pythonModuleName);
  return module;
}

- (void)appendPythonPath:(NSString *)path {
  if (vermilionModule_) {
    if ([path length]) {
      PythonStackLock gilLock;
      // PyModule_GetDict() returns a weak ref, does not need to be freed
      PyObject *moduleDict = PyModule_GetDict(vermilionModule_);
      if (moduleDict) {
        // PyDict_GetItemString() returns a weak ref
        PyObject *func = PyDict_GetItemString(moduleDict, kAddSysPathFuncName);
        if (func && PyCallable_Check(func))  {
          PyObject *args = PyTuple_New(1);
          PyTuple_SetItem(args, 0, PyString_FromString([path UTF8String]));
          PyObject *result = PyObject_CallObject(func, args);
          if (result) {
            if (!PyBool_Check(result) || result != Py_True) {
              NSString *error = [HGSPython lastErrorString];
              HGSLogDebug(@"%s('%@') returned false.\n%@", 
                          kAddSysPathFuncName, path, error);
            }
            Py_DECREF(result);
          } else {
            NSString *error = [HGSPython lastErrorString];
            HGSLogDebug(@"failed to call %s('%@')\n%@", 
                        kAddSysPathFuncName, path, error);
          }
          Py_DECREF(args);
        }
      }
    } else {
      HGSLogDebug(@"empty path, cannot append");
    }
  }
}

+ (NSString *)stringAttribute:(NSString *)attr fromObject:(PyObject *)obj {
  NSString *result = nil;
  if (obj) {
    PyObject *pythonStr = PyObject_GetAttrString(obj, [attr UTF8String]);
    if (pythonStr) {
      // PyString_AsString() returns internal reprensentation, should
      // not be modified or freed
      char *buffer = PyString_AsString(pythonStr);
      if (buffer) {
        result = [NSString stringWithUTF8String:buffer];
      }
      Py_DECREF(pythonStr);
    }
  }
  return result;
}

+ (NSString *)lastErrorString {
  NSString *result = nil;
  PyObject *ptype, *pvalue, *ptraceback;
  PyErr_Fetch(&ptype, &pvalue, &ptraceback);
  PyErr_NormalizeException(&ptype, &pvalue, &ptraceback);
  const char *pTypeString = ptype ? PyString_AsString(ptype) : "Unknown";
  const char *pValueString = pvalue ? PyString_AsString(pvalue) : "Unknown";
  NSString *tracebackString = nil;
  PyObject *tracebackModule = PyImport_ImportModule("traceback");
  if (tracebackModule != NULL) {
    PyObject *tbList= PyObject_CallMethod(tracebackModule,
                                          (char *)"format_exception",
                                          (char *)"OOO",
                                          ptype,
                                          pvalue == NULL ? Py_None 
                                                         : pvalue,
                                          ptraceback == NULL ? Py_None 
                                                             : ptraceback);
    if (tbList) {
     PyObject *emptyString = PyString_FromString("");
      if (emptyString) {
        // The "O" is a format string that represents that the item tbList
        // is a python object.
        PyObject *strRetval = PyObject_CallMethod(emptyString, (char *)"join",
                                                  (char *)"O", tbList);
        if (strRetval) {
          const char *ptracebackString = PyString_AsString(strRetval);
          tracebackString = [NSString stringWithUTF8String:ptracebackString];
          Py_DECREF(strRetval);
        }
        Py_DECREF(emptyString);
      }
      Py_DECREF(tbList);
    }
    Py_DECREF(tracebackModule);
  }
  if (!tracebackString) {
    tracebackString = @"Traceback: Couldn't load traceback module.";
  }
  result = [NSString stringWithFormat:@"Python Error. Type: %s\n"
            @"             Value: %s\n         %@",
            pTypeString, pValueString, tracebackString];
  if (ptype) Py_DECREF(ptype);
  if (pvalue) Py_DECREF(pvalue);
  if (ptraceback) Py_DECREF(ptraceback);
  return result;
}

@end // HGSPython

#pragma mark Python Query Object

// Constructor creates members, but doesn't set their initial values
static PyObject *QueryNew(PyTypeObject *type, PyObject *args, PyObject *kwds) {
  Query *self = (Query *)type->tp_alloc(type, 0);
  if (self) {
    self->operation_ = nil;
    self->rawQuery_ = PyString_FromString("");
    if (!self->rawQuery_) {
      Py_DECREF(self);
      return nil;
    }
    self->normalizedQuery_ = PyString_FromString("");
    if (!self->normalizedQuery_) {
      Py_DECREF(self);
      return nil;
    }
    self->pivotObject_ = PyDict_New();
    if (!self->pivotObject_) {
      Py_DECREF(self);
      return nil;
    }
  }
  return (PyObject *)self;
}

// Destructor
static void QueryDealloc(Query *self) {
    Py_XDECREF(self->rawQuery_);
    Py_XDECREF(self->normalizedQuery_);
    Py_XDECREF(self->pivotObject_);
    [self->operation_ release];
    self->ob_type->tp_free((PyObject *)self);
}

// Like Obj-C, the Python C API uses a two step alloc/init process
static int QueryInit(Query *self, PyObject *args, PyObject *kwds) {
  static const char *kwlist[] = {
    kHGSPythonNormalizedQueryMemberName,
    kHGSPythonRawQueryMemberName,
    kHGSPythonPivotObjectMemberName,
    nil
  };
  PyObject *normalizedQuery = nil, *rawQuery = nil, *pivotObject = nil, *tmp;
  if (!PyArg_ParseTupleAndKeywords(args, kwds, "|OOO", 
                                   const_cast<char**>(kwlist), &normalizedQuery, 
                                   &rawQuery, &pivotObject)) {
    return -1;
  }
  if (normalizedQuery) {
    tmp = self->normalizedQuery_;
    Py_INCREF(normalizedQuery);
    self->normalizedQuery_ = normalizedQuery;
    Py_XDECREF(tmp);
  }
  if (rawQuery) {
    tmp = self->rawQuery_;
    Py_INCREF(rawQuery);
    self->rawQuery_ = rawQuery;
    Py_XDECREF(tmp);
  }
  if (pivotObject) {
    tmp = self->pivotObject_;
    Py_INCREF(pivotObject);
    self->pivotObject_ = pivotObject;
    Py_XDECREF(tmp);
  }
  return 0;
}

static PyObject *QueryGetAttr(Query *self, char *name) {
  PyObject *result = nil;

  if (!strcmp(name, kHGSPythonNormalizedQueryMemberName)) {
    result = self->normalizedQuery_;
  } else if (!strcmp(name, kHGSPythonRawQueryMemberName)) {
    result = self->rawQuery_;
  } else if (!strcmp(name, kHGSPythonPivotObjectMemberName)) {
    result = self->pivotObject_;
  }
  
  if (result) {
    Py_INCREF(result);
  } else {
    result = Py_FindMethod(QueryMethods, (PyObject *)self, name);
  }
  
  return result;
}

static int QuerySetAttr(Query *self, char *name, PyObject *value) {
  // All attributes are read-only
  return 0;
}

static PyObject *QuerySetResults(Query *self, PyObject *args) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  PyObject *pythonResults = nil;
  if (PyArg_ParseTuple(args, "O", &pythonResults)) {
    NSMutableArray *results = [NSMutableArray array];
    // Generate a "real" result from each of the Python results
    if (pythonResults) {
      if (PyList_Check(pythonResults)) {
        Py_ssize_t resultCount = PyList_Size(pythonResults);
        for (Py_ssize_t i = 0; i < resultCount; ++i) {
          PyObject *dict = PyList_GET_ITEM(pythonResults, i);
          char *identifier = nil, *displayName = nil, *snippet = nil;
          char *image = nil, *defaultAction = nil;
          NSString *type = kHGSTypePython;
          if (PyDict_Check(dict)) {
            NSMutableDictionary *privateValues 
              = [NSMutableDictionary dictionary];
            PyObject *pyKey, *pyValue;
            Py_ssize_t pos = 0;
            while (PyDict_Next(dict, &pos, &pyKey, &pyValue)) {
              if (PyString_Check(pyKey)) {
                NSString *key = [NSString
                                 stringWithUTF8String:PyString_AsString(pyKey)];
                if ([key isEqual:kHGSObjectAttributeURIKey]) {
                  if (PyString_Check(pyValue)) {
                    identifier = PyString_AsString(pyValue);
                  }
                } else if ([key isEqual:kHGSObjectAttributeNameKey]) {
                  if (PyString_Check(pyValue)) {
                    displayName = PyString_AsString(pyValue);
                  }
                } else if ([key isEqual:kHGSObjectAttributeSnippetKey]) {
                  if (PyString_Check(pyValue)) {
                    snippet = PyString_AsString(pyValue);
                  }
                } else if ([key isEqual:kHGSObjectAttributeIconPreviewFileKey]) {
                  if (PyString_Check(pyValue)) {
                    image = PyString_AsString(pyValue);
                  }
                } else if ([key isEqual:kHGSObjectAttributeDefaultActionKey]) {
                  if (PyString_Check(pyValue)) {
                    defaultAction = PyString_AsString(pyValue);
                  }
                } else if ([key isEqual:kHGSObjectAttributeTypeKey]) {
                  if (PyString_Check(pyValue)) {
                    type = [NSString stringWithUTF8String:
                            PyString_AsString(pyValue)];
                  }
                } else if (pyValue) {
                  HGSPythonObject *pyObj 
                    = [HGSPythonObject pythonObjectWithObject:pyValue];
                  [privateValues setObject:pyObj forKey:key];
                }
              }
            }
            if (identifier) {
              // TODO(dmaclach): Update the following ranking approach
              // at the appropriate time.
              CGFloat rank = 0.0;
              NSString *displayNameString = nil;
              if (displayName) {
                displayNameString = [NSString stringWithUTF8String:displayName];
                NSString *normalizedDisplayName
                  = [HGSTokenizer tokenizeString:displayNameString];

                const char *queryCString
                  = PyString_AsString(self->normalizedQuery_);
                NSString *queryString
                  = [NSString stringWithUTF8String:queryCString];
                rank = HGSScoreTermForItem(queryString, 
                                           normalizedDisplayName,
                                           NULL);
              }
              if (rank > 0.0) {
                NSMutableDictionary *attributes 
                  = [NSMutableDictionary
                     dictionaryWithObject:[NSNumber numberWithFloat:rank]
                                   forKey:kHGSObjectAttributeRankKey];
                NSString *urlString = [NSString stringWithUTF8String:identifier];
                if (snippet && strlen(snippet) > 0) {
                  [attributes setObject:[NSString stringWithUTF8String:snippet]
                                 forKey:kHGSObjectAttributeSnippetKey];
                }
                if (defaultAction && strlen(defaultAction) > 0) {
                  HGSAction *action 
                    = [[HGSExtensionPoint actionsPoint] extensionWithIdentifier:
                       [NSString stringWithUTF8String:defaultAction]];
                  if (action) {
                    [attributes setObject:action 
                                   forKey:kHGSObjectAttributeDefaultActionKey];
                  }
                }
                if (image && strlen(image) > 0) {
                  NSString *imageURLString = [NSString stringWithUTF8String:image];
                  NSURL *imageURL = [NSURL URLWithString:imageURLString];
                  if (![imageURL scheme]) {
                    // If they didn't give us a full URL, let's look in our
                    // bundle.
                    NSBundle *bundle = [[self->operation_ source] bundle];
                    NSString *extension = [imageURLString pathExtension];
                    NSString *path
                      = [imageURLString stringByDeletingPathExtension];
                    NSString *imagePath = [bundle pathForResource:path
                                                           ofType:extension];
                    if ([imagePath length]) {
                      NSImage *icon 
                        = [[[NSImage alloc] initByReferencingFile:imagePath]
                           autorelease];
                      [attributes setObject:icon
                                     forKey:kHGSObjectAttributeIconKey];
                      imageURL = nil;
                    } else {
                      imagePath = [bundle pathForResource:imageURLString
                                                   ofType:nil];
                      if ([imagePath length]) {
                        imageURL = [NSURL fileURLWithPath:imagePath
                                              isDirectory:NO];
                      }
                    }
                  }
                  if (imageURL) {
                    [attributes setObject:imageURL 
                                   forKey:kHGSObjectAttributeIconPreviewFileKey];
                  }
                }
                [attributes setObject:privateValues 
                             forKey:kHGSPythonPrivateValuesKey];
                HGSResult *result 
                  = [HGSResult resultWithURI:urlString
                                        name:displayNameString
                                        type:type
                                      source:[self->operation_ source]
                                  attributes:attributes];
                if (result) {
                  [results addObject:result];
                }
              }
            }
          }
        }
      }
      Py_DECREF(pythonResults);
    }
    [self->operation_ performSelectorOnMainThread:@selector(setResults:)
                                       withObject:results
                                    waitUntilDone:NO];
  }
  
  [pool release];

  Py_RETURN_NONE;
}

static PyObject *QueryFinish(Query *self, PyObject *unused) {
  [self->operation_ performSelectorOnMainThread:@selector(finishQuery)
                                     withObject:nil
                                  waitUntilDone:NO];
  Py_RETURN_NONE;
}

static PyObject *LocalizeString(PyObject *self, PyObject *args) {
  char *str;
  if (!PyArg_ParseTuple(args, "s", &str)) {
    HGSLogDebug(@"VermilionLocalize.String() requires an argument");
    return PyString_FromString("");
  }
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSBundle *bundle = [[[NSThread currentThread] threadDictionary]
                      valueForKey:kHGSPythonThreadBundleKey];
  NSString *key = [NSString stringWithUTF8String:str];
  NSString *localized = [bundle localizedStringForKey:key value:@"" table:nil];
  PyObject *resultString = nil;
  if (localized) {
    resultString = PyString_FromString([localized UTF8String]);
  } else {
    resultString = PyString_FromString(str);
  }
  [pool release];
  return resultString;
}
