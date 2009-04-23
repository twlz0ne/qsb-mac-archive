#!/usr/bin/python
#
#  ___PROJECTNAMEASIDENTIFIER___.py
#  ___PROJECTNAME___
#
#  Created by ___FULLUSERNAME___ on ___DATE___.
#  Copyright ___ORGANIZATIONNAME___ ___YEAR___. All rights reserved.
#

"""A python search source for QSB.
"""

__author__ = '___FULLUSERNAME___'

import sys
import thread
import AppKit
import Foundation

try:
  import Vermilion  # pylint: disable-msg=C6204
except ImportError:

  class Vermilion(object):
    """A mock implementation of the Vermilion class.

    Vermilion is provided in native code by the QSB
    runtime. We create a stub Result class here so that we
    can develop and test outside of QSB from the command line.
    """
    
    IDENTIFIER = 'IDENTIFIER'
    DISPLAY_NAME = 'DISPLAY_NAME'
    SNIPPET = 'SNIPPET'
    IMAGE = 'IMAGE'
    DEFAULT_ACTION = 'DEFAULT_ACTION'

    class Query(object):
      """A mock implementation of the Vermilion.Query class.

      Vermilion is provided in native code by the QSB
      runtime. We create a stub Result class here so that we
      can develop and test outside of QSB from the command line.
      """
      
      def __init__(self, phrase):
        self.raw_query = phrase
        self.normalized_query = phrase
        self.pivot_object = None
        self.finished = False
        self.results = []

      def SetResults(self, results):
        self.results = results

      def Finish(self):
        self.finished = True

CUSTOM_RESULT_VALUE = 'CUSTOM_RESULT_VALUE'

class ___PROJECTNAMEASIDENTIFIER___Search(object):
  """___PROJECTNAMEASIDENTIFIER___ search source.

  This class conforms to the QSB search source protocol by
  providing the mandatory PerformSearch method and the optional
  IsValidSourceForQuery method.

  """

  def PerformSearch(self, query):
    """Performs the search.

    Args:
      query: A Vermilion.Query object containing the user's search query
    """
    results = [];
    result = {};
    result[Vermilion.IDENTIFIER] = '___PROJECTNAMEASIDENTIFIER___://result';
    result[Vermilion.SNIPPET] = 'So here\'s a bunny with a pancake on it\'s head!';
    result[Vermilion.IMAGE] = '___PROJECTNAMEASIDENTIFIER___.png';
    result[Vermilion.DISPLAY_NAME] = '___PROJECTNAMEASIDENTIFIER___ Result';
    result[Vermilion.DEFAULT_ACTION] = 'com.yourcompany.action.___PROJECTNAMEASIDENTIFIER___';
    result[CUSTOM_RESULT_VALUE] = 'http://www.fsinet.or.jp/~sokaisha/rabbit/rabbit.htm';
    results.append(result);
    query.SetResults(results)
    query.Finish()

  def IsValidSourceForQuery(self, query):
    """Determines if the search source is willing to handle the query.

    Args:
      query: A Vermilion.Query object containing the user's search query

    Returns:
      True if our source handles the query
    """
    return True
    
class ___PROJECTNAMEASIDENTIFIER___Action(object):
  """___PROJECTNAMEASIDENTIFIER___ Action

  This class conforms to the QSB search action protocol by
  providing the mandatory AppliesToResults and Perform methods.
  
  """
  def AppliesToResults(self, result):
    """Determines if the result is one we can act upon."""
    return True

  def Perform(self, results):
    """Perform the action"""
    for result in results:
      url = Foundation.NSURL.URLWithString_(result[CUSTOM_RESULT_VALUE])
      workspace = AppKit.NSWorkspace.sharedWorkspace()
      workspace.openURL_(url)

def main():
  """Command line interface for easier testing."""
  argv = sys.argv[1:]
  if not argv:
    print 'Usage: ___PROJECTNAMEASIDENTIFIER___ <query>'
    return 1

  query = Vermilion.Query(argv[0])
  search = ___PROJECTNAMEASIDENTIFIER___Search()
  if not search.IsValidSourceForQuery(Vermilion.Query(argv[0])):
    print 'Not a valid query'
    return 1
  search.PerformSearch(query)

  while query.finished is False:
    time.sleep(1)

  for result in query.results:
    print result


if __name__ == '__main__':
  sys.exit(main())
