import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from launch import configure


class LocalConfigurationTests(unittest.TestCase):
    def test_local_file_loads_without_environment_or_cli(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            path = Path(directory) / '.env'
            path.write_text('AZURE_OPENAI_API_KEY=test-only\nAZURE_OPENAI_DEPLOYMENT=my-model\n')
            configure(path, interactive=False)
            self.assertEqual(os.environ['AZURE_OPENAI_API_KEY'], 'test-only')
            self.assertEqual(os.environ['AZURE_OPENAI_DEPLOYMENT'], 'my-model')

    def test_environment_takes_precedence_and_values_are_literal(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'AZURE_OPENAI_API_KEY': 'environment-test-key'}, clear=True):
            path = Path(directory) / '.env'
            path.write_text('AZURE_OPENAI_API_KEY=file-test-key\nAZURE_OPENAI_DEPLOYMENT=${DO_NOT_EXPAND}\n')
            configure(path, interactive=False)
            self.assertEqual(os.environ['AZURE_OPENAI_API_KEY'], 'environment-test-key')
            self.assertEqual(os.environ['AZURE_OPENAI_DEPLOYMENT'], '${DO_NOT_EXPAND}')

    def test_first_run_saves_key_without_printing_it(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            path = Path(directory) / '.env'
            output = io.StringIO()
            with patch('builtins.input', side_effect=['', '']), patch('getpass.getpass', return_value='test-only-hidden-key'), contextlib.redirect_stdout(output):
                configure(path)
            self.assertNotIn('test-only-hidden-key', output.getvalue())
            self.assertIn('test-only-hidden-key', path.read_text())

    def test_missing_key_and_insecure_endpoint_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            path = Path(directory) / '.env'
            with self.assertRaises(ValueError):
                configure(path, interactive=False)
            os.environ.update(AZURE_OPENAI_API_KEY='test-only', AZURE_OPENAI_ENDPOINT='http://example.invalid')
            with self.assertRaises(ValueError):
                configure(path, interactive=False)


if __name__ == '__main__':
    unittest.main()
