//
//  HGSMixer.m
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

#import "HGSMixer.h"

#include <CoreServices/CoreServices.h>
#include <mach/mach_time.h>

#import "HGSQueryController.h"
#import "HGSResult.h"
#import "HGSSearchOperation.h"
#import "HGSLog.h"
#import "HGSBundle.h"
#import "GTMDebugThreadValidation.h"

inline NSInteger HGSMixerResultSort(id resultA, id resultB, void* context) {
  HGSResult *a = (HGSResult *)resultA;
  HGSResult *b = (HGSResult *)resultB;
  NSInteger result = NSOrderedSame;
  CGFloat rankA = [a rank];
  CGFloat rankB = [b rank]; 
  if (rankA > rankB) {
    result = NSOrderedAscending;
  } else if (rankA < rankB) {
    result = NSOrderedDescending;
  }
  return result;
}

@interface HGSMixer()
+ (NSString *)categoryForType:(NSString *)type;
@end

@implementation HGSMixer

- (id)initWithDelegate:(id<HGSMixerDelegate>)delegate
                 range:(NSRange)range 
      searchOperations:(NSArray *)ops 
         firstInterval:(NSTimeInterval)firstInterval 
      progressInterval:(NSTimeInterval)progressInterval {
  if ((self = [super init])) {
    range_ = range;
    ops_ = [ops copy];
    results_ = [[NSMutableArray alloc] initWithCapacity:NSMaxRange(range)];
    resultsByCategory_ = [[NSMutableDictionary alloc] init];
    
    firstInterval_ = UnsignedWideToUInt64(DurationToAbsolute(firstInterval * 1000));
    progressInterval_ = UnsignedWideToUInt64(DurationToAbsolute(progressInterval * 1000));
    delegate_ = delegate;
  }
  return self;
}

- (void)dealloc {
  [ops_ release];
  [results_ release];
  [resultsByCategory_ release];
  [super dealloc];
}

- (void)main {
  NSUInteger maxLength = NSMaxRange(range_);
  NSUInteger opsCount = [ops_ count];
  NSInteger *opsIndices = calloc(sizeof(NSInteger), opsCount);
  NSInteger *opsMaxIndices = malloc(sizeof(NSInteger) * opsCount);
  NSUInteger currentIndex = 0;
  
  NSUInteger opsIndex = 0;
  for (HGSSearchOperation *op in ops_) {
    opsMaxIndices[opsIndex] = [op resultCount];
    ++opsIndex;
  }
  
  uint64_t startTime = mach_absolute_time();
  
  // Perform merge sort where we take the top ranked result in each
  // queue and add it to the sorted results.
  while (currentIndex < maxLength) {
    HGSResult *newResult = nil;
    NSUInteger indexToIncrement = 0;
    for (NSUInteger i = 0; i < opsCount; ++i) {
      HGSResult *testResult = nil;
      if (opsIndices[i] < opsMaxIndices[i]) {
        testResult = [[ops_ objectAtIndex:i] sortedResultAtIndex:opsIndices[i]];
        NSInteger compare = HGSMixerResultSort(testResult, newResult, nil);
        if (compare == NSOrderedAscending) {
          newResult = testResult;
          indexToIncrement = i;
        }
      }
    }
    if (newResult) {
      NSUInteger resultIndex = 0;
      @synchronized (results_) {
        for (HGSResult *result in results_) {
          if ([result isDuplicate:newResult]) {
            newResult = [result mergeWith:newResult];
            [results_ replaceObjectAtIndex:resultIndex withObject:newResult];
            newResult = nil;
            break;
          }
          ++resultIndex;
        }
        if (newResult) {
          [results_ addObject:newResult];
          NSString *type = [newResult type];
          if (type && ![newResult conformsToType:kHGSTypeSuggest]) {
            NSString *category = [[self class] categoryForType:type];
            // Fallback to type if necessary.
            if (!category) {
              category = type;
            }
            NSMutableArray *array = [resultsByCategory_ objectForKey:category];
            if (!array) {
              array = [NSMutableArray arrayWithObject:newResult];
              [resultsByCategory_ setObject:array forKey:category];
            } else {
              [array addObject:newResult];
            }
          }
          currentIndex++;
        }
        opsIndices[indexToIncrement]++;
      }
    } else {
      break;
    }
    if ([self isCancelled]) {
      break;
    }
    uint64_t intervalToCheck = firstInterval_;
    if (!intervalToCheck) {
      intervalToCheck = progressInterval_;
    }
    if (intervalToCheck) {
      uint64_t currentTime = mach_absolute_time();
      uint64_t deltaTime = currentTime - startTime;
      if (deltaTime > intervalToCheck) {
        if (![NSThread isMainThread]) {
          [delegate_ performSelectorOnMainThread:@selector(mixerDidUpdateResults:)
                                      withObject:self
                                   waitUntilDone:NO];
        } else {
          [delegate_ mixerDidUpdateResults:self];
        }
        firstInterval_ = 0;
        startTime = mach_absolute_time();
      }
    }
  }
  free(opsIndices);
  free(opsMaxIndices);
  if (![NSThread isMainThread]) {
    [delegate_ performSelectorOnMainThread:@selector(mixerDidStop:)
                                withObject:self
                             waitUntilDone:NO];
  } else {
    [delegate_ mixerDidStop:self];
  }
}

- (NSArray *)rankedResults {
  NSArray *value = nil;
  @synchronized (results_) {
    value = [[results_ copy] autorelease];
  }
  return value;
}

- (NSDictionary *)rankedResultsByCategory {
  NSDictionary *categoryResults = nil;
  // Synchronizing on results_ here is intentional. results_ is being used
  // as the synchronization semaphore for all of the variables.
  @synchronized (results_) {
    // Must do a semi-deep copy as we need non-mutable arrays in our dictionary
    // copy because other threads are going to be accessing them.
    NSArray *keys = [resultsByCategory_ allKeys];
    NSArray *objects = [resultsByCategory_ objectsForKeys:keys
                                           notFoundMarker:[NSNull null]];
    NSMutableArray *newObjects 
      = [NSMutableArray arrayWithCapacity:[objects count]];
    for (id value in objects) {
      HGSAssert([value isKindOfClass:[NSArray class]], nil);
      [newObjects addObject:[value copy]];
    }
    categoryResults = [NSDictionary dictionaryWithObjects:newObjects 
                                                  forKeys:keys];
  }
  return categoryResults;
}

static NSMutableDictionary *sTypeCategoryDict = nil;

+ (void)initialize {
  if (!sTypeCategoryDict) {
    NSBundle *bundle = HGSGetPluginBundle();
    // Pull in our type->category dictionary.
    NSString *plistPath = [bundle pathForResource:@"TypeCategories"
                                           ofType:@"plist"];
    if (plistPath) {
      sTypeCategoryDict 
        = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
    }
    if (!sTypeCategoryDict) {
      HGSLogDebug(@"TypeCategories.plist cannot be found in the app bundle.");
    }
  }
}

+ (NSString *)categoryForType:(NSString *)type {  
  if (!type) return nil;
  NSString *category = nil;
  NSString *searchType = type;
  BOOL addNewMapping = NO;
  @synchronized(sTypeCategoryDict) {
    while ([searchType length]
           && !(category = [sTypeCategoryDict objectForKey:searchType])) {
      addNewMapping = YES;  // Signal that we should cache a new mapping.
      NSRange dotRange = [searchType rangeOfString:@"." 
                                           options:NSBackwardsSearch];
      if (dotRange.location != NSNotFound) {
        searchType = [searchType substringToIndex:dotRange.location];
      } else {
        searchType = nil;  // Not found.
        category = @"^Others";
        HGSLogDebug(@"No category found for type '%@'.  Using 'Others'.", type);
      }
    }
    
    if (addNewMapping && category) {
      [sTypeCategoryDict setObject:category forKey:type];
    }
  }
  return category;
}


@end

