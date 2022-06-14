import pytest
import unittest

# Add test utils to path during test runs
# print(os.path.join(os.path.dirname(__file__), 'utils'))
# sys.path.append(os.path.join(os.path.dirname(__file__), 'utils'))

# Set maxDiff to None so pytest shows which values in the dictionaries are incorrect.
@pytest.fixture(scope='package', autouse=True)
def set_MaxDiff_to_None():
    unittest.TestCase.maxDiff = None
