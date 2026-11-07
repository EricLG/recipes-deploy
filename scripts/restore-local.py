"""Restore a recipes-backup-v1 archive to the local development environment."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import socket
import subprocess
import tarfile
import tempfile
import uuid

TOOLS = Path(__file__).resolve().parent
PROJECT = TOOLS.parent
BACKEND = PROJECT.parent / 'recipes-back'
UPLOADS = BACKEND / 'uploads'
PARTS = ('format', 'database', 'mongodb.gz', 'uploads.tar.gz', 'SHA256SUMS')


def unpack(archive, work):
    """Validate before writing; never trust archive paths or links."""
    with tarfile.open(archive, 'r:gz') as source:
        members = source.getmembers()
        if sorted(m.name for m in members) != sorted(PARTS) or any(not m.isfile() for m in members):
            raise ValueError('Archive must be a complete recipes-backup-v1 backup')
        for member in members:
            with source.extractfile(member) as stream, (work / member.name).open('wb') as dest:
                shutil.copyfileobj(stream, dest)
    if (work / 'format').read_bytes() != b'recipes-backup-v1\n':
        raise ValueError('Unsupported backup version')
    checksums = []
    for name in PARTS[:4]:
        with (work / name).open('rb') as stream:
            checksums.append(f'{hashlib.file_digest(stream, "sha256").hexdigest()}  {name}\n')
    expected = ''.join(checksums)
    if (work / 'SHA256SUMS').read_text() != expected:
        raise ValueError('Invalid archive checksums')
    with gzip.open(work / 'mongodb.gz', 'rb') as dump:
        while dump.read(1024 * 1024):
            pass
    staging = work / 'uploads'
    staging.mkdir()
    with tarfile.open(work / 'uploads.tar.gz', 'r:gz') as images:
        members = images.getmembers()
        normalized = set()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or '\\' in member.name or ':' in member.name:
                raise ValueError('Unsafe upload path')
            if not (member.isfile() or member.isdir()):
                raise ValueError('Upload links and special files are forbidden')
            key = str(path).casefold()
            if key in normalized:
                raise ValueError('Duplicate or case-colliding upload paths')
            normalized.add(key)
        for member in members:
            dest = staging.joinpath(*PurePosixPath(member.name).parts)
            if member.isdir():
                dest.mkdir(parents=True, exist_ok=True)
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                with images.extractfile(member) as stream, dest.open('wb') as target:
                    shutil.copyfileobj(stream, target)
    return (work / 'database').read_text().strip(), staging


def helper(command):
    result = subprocess.run(['node', str(TOOLS / 'src' / 'local-mongo.cjs'), command],
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout else None


def mongo_tool(name, uri, *args):
    # Capture diagnostics to avoid leaking URI credentials into logs.
    result = subprocess.run([name, '--uri', uri, *args], capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{name} failed (exit {result.returncode}); local recovery files retained')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--yes', action='store_true', help='Confirm replacement of local database and images')
    options = parser.parse_args()
    # Always resolve explicitly: never silently select another backup.
    archive = options.archive.resolve(strict=True)
    (PROJECT.parent / 'backups').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='recipes-restore-', dir=PROJECT.parent / 'backups') as temporary:
        work = Path(temporary)
        database, staging = unpack(archive, work)
        image_count = sum(p.is_file() for p in staging.rglob('*'))
        print(f'Archive verified: database {database}, {image_count} image files')
        if options.verify_only:
            return
        for tool in ('node', 'mongodump', 'mongorestore'):
            if not shutil.which(tool):
                raise RuntimeError(f'Missing command: {tool}')
        config = helper('config')
        if config['database'] != database:
            raise ValueError('Archive database differs from recipes-back/.env database')
        for address in ('127.0.0.1', '::1'):
            with socket.socket(socket.AF_INET6 if ':' in address else socket.AF_INET) as probe:
                probe.settimeout(0.3)
                if probe.connect_ex((address, 3000)) == 0:
                    raise RuntimeError('Stop the development backend on port 3000 before restoring')
        before = helper('inspect')
        print(f'Local target: {database}; images: {UPLOADS}')
        if not options.yes and input('Type RESTORE to replace local data: ') != 'RESTORE':
            raise RuntimeError('Restore cancelled')
        if UPLOADS.is_symlink() or UPLOADS.is_junction():
            raise ValueError('Uploads must be a normal directory')
        recovery = PROJECT.parent / 'backups' / ('local-before-' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S') + '-' + uuid.uuid4().hex[:8])
        recovery.mkdir()
        mongo_tool('mongodump', config['uri'], '--db=' + database,
                   '--archive=' + str(recovery / 'mongodb.gz'), '--gzip')
        (recovery / 'counts.json').write_text(json.dumps(before, indent=2))
        if UPLOADS.exists():
            shutil.copytree(UPLOADS, recovery / 'uploads')
        else:
            (recovery / 'uploads').mkdir()
        print(f'Previous local state saved: {recovery}')
        helper('drop')
        mongo_tool('mongorestore', config['uri'], '--archive=' + str(work / 'mongodb.gz'), '--gzip',
                   '--nsInclude=' + database + '.*', '--stopOnError')
        # Rename instead of recursively deleting the existing uploads directory.
        old = BACKEND / ('uploads.before-' + recovery.name)
        if UPLOADS.exists():
            UPLOADS.rename(old)
            old.rename(recovery / 'uploads-original')
        # Create under the backend so Windows inherits its ACLs. Moving a
        # TemporaryDirectory would preserve its owner-only ACL and block the
        # developer's normal Node process even though our own checks succeed.
        shutil.copytree(staging, UPLOADS)
        after = helper('inspect')
        print(json.dumps(after, indent=2))
        if after['missingImages']:
            raise RuntimeError('Restore completed but some recipe image files are missing')
        print('Local database and images restored. You can start the development backend.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, tarfile.TarError) as error:
        # CalledProcessError may contain sensitive subprocess arguments.
        print('Restore failed: ' + (str(error) if not isinstance(error, subprocess.CalledProcessError)
                                   else 'Local MongoDB helper failed; check local configuration/server'))
        raise SystemExit(1)
