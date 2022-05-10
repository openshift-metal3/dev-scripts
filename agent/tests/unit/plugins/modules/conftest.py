import pytest
import unittest

# Set maxDiff to None so pytest shows which values in the dictionaries are incorrect.
@pytest.fixture(scope='package', autouse=True)
def set_MaxDiff_to_None():
    unittest.TestCase.maxDiff = None