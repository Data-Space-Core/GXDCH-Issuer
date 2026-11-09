import importlib.util
from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "platform-apps" / "gxdch-issuer" / "core"
spec = importlib.util.spec_from_file_location("did_proxy_config", CORE / "did-proxy-config.py")
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


class BootstrapTests(unittest.TestCase):
    def test_seed_job_is_recreated_not_patched(self):
        job = yaml.safe_load((CORE / "vault-seed-job.yaml").read_text())
        annotations = job["metadata"]["annotations"]
        self.assertEqual(annotations["argocd.argoproj.io/hook"], "Sync")
        self.assertIn("BeforeHookCreation", annotations["argocd.argoproj.io/hook-delete-policy"].split(","))
        self.assertIn("HookSucceeded", annotations["argocd.argoproj.io/hook-delete-policy"].split(","))
        command = job["spec"]["template"]["spec"]["containers"][0]["command"][-1]
        self.assertIn("set -eu", command)
        self.assertIn('if [ "$current" != "$2" ]', command)
        self.assertNotIn("genkey", command)

    def test_proxy_uses_published_document_not_bootstrap_key(self):
        for host in ("research.example.org", "lab-two.example.org"):
            config = proxy.render_proxy_config({"id": f"did:web:{host}:issuer", "verificationMethod": [{"stale": True}]})
            self.assertIn("proxy_pass http://dataspace-issuer-service:10016/issuer/did.json;", config)
            self.assertIn(f"proxy_set_header Host {host};", config)
            self.assertNotIn("alias", config)
            self.assertNotIn("stale", config)

    def test_domain_only_did_and_encoded_port(self):
        config = proxy.render_proxy_config({"id": "did:web:issuer.example.org%3A8443"})
        self.assertIn("Host issuer.example.org:8443;", config)
        self.assertIn("10016/.well-known/did.json;", config)

    def test_invalid_identifiers_do_not_reach_nginx_config(self):
        for did in ("did:key:bad", "did:web:example.org;injected", "did:web:example.org\ninvalid",
                    "did:web:example.org:..", "did:web:example.org:"):
            with self.subTest(did=did), self.assertRaises(ValueError):
                proxy.render_proxy_config({"id": did})
