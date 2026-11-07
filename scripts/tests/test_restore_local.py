import gzip
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('restore', Path(__file__).resolve().parents[1] / 'restore-local.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class ArchiveTests(unittest.TestCase):
    def archive(self, root, image_path='./recipes/photo.png', corrupt=False, link=False):
        images = io.BytesIO()
        with tarfile.open(fileobj=images, mode='w:gz') as tar:
            member = tarfile.TarInfo(image_path)
            if link:
                member.type = tarfile.SYMTYPE
                member.linkname = '/elsewhere'
                tar.addfile(member)
            else:
                member.size = 5
                tar.addfile(member, io.BytesIO(b'image'))
        parts = {'format': b'recipes-backup-v1\n', 'database': b'recipes',
                 'mongodb.gz': gzip.compress(b'dump'), 'uploads.tar.gz': images.getvalue()}
        parts['SHA256SUMS'] = ''.join(f'{hashlib.sha256(parts[n]).hexdigest()}  {n}\n'
                                      for n in restore.PARTS[:4]).encode()
        if corrupt:
            parts['database'] = b'changed'
        archive = root / 'backup.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            for name, data in parts.items():
                member = tarfile.TarInfo(name)
                member.size = len(data)
                tar.addfile(member, io.BytesIO(data))
        return archive

    def test_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database, images = restore.unpack(self.archive(root), root)
            self.assertEqual(database, 'recipes')
            self.assertEqual((images / 'recipes/photo.png').read_bytes(), b'image')

    def test_reject_unsafe_or_corrupted(self):
        for options in ({'image_path': '../outside'}, {'image_path': '/absolute'},
                        {'image_path': './C:/file'}, {'link': True}, {'corrupt': True}):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with self.assertRaises(ValueError):
                    restore.unpack(self.archive(root, **options), root)


if __name__ == '__main__':
    unittest.main()
