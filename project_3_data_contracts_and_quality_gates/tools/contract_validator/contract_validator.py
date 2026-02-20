"""
Data Contract Validator
Validates CDC and Metrics contracts against actual data
"""

import yaml
import json
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ContractValidator:
    """Validates data contracts"""
    
    def __init__(self, contracts_dir: str = None):
        self.contracts_dir = Path(contracts_dir or "contracts")
        self.violations = []
    
    def load_contract(self, contract_path: Path) -> Dict[str, Any]:
        """Load contract from YAML file"""
        with open(contract_path, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    
    def validate_cdc_event(self, contract: Dict[str, Any], event: Dict[str, Any]) -> List[str]:
        """
        Validate a CDC event against contract
        
        Returns list of violation messages (empty if valid)
        """
        violations = []
        
        # Check required envelope fields
        required_fields = contract.get('required_envelope_fields', [])
        for field in required_fields:
            if field not in event:
                violations.append(f"Missing required envelope field: {field}")
        
        # Check op semantics
        op = event.get('op')
        if op:
            allowed_ops = contract.get('op_semantics', {}).get('allowed_ops', [])
            if op not in allowed_ops:
                violations.append(f"Invalid op: {op}, allowed: {allowed_ops}")
        
        # Check payload rules
        payload_rules = contract.get('payload_rules', {})
        after_required = payload_rules.get('after_required_when_op', [])
        if op in after_required and 'after' not in event:
            violations.append(f"Missing 'after' field when op={op}")
        
        # Check delete rules
        if op == 'd':
            delete_rules = payload_rules.get('delete_rules', {})
            if delete_rules.get('after_must_be_null', False):
                if event.get('after') is not None:
                    violations.append("Delete operation: 'after' must be null")
            if delete_rules.get('before_should_exist', False):
                if 'before' not in event:
                    violations.append("Delete operation: 'before' should exist")
        
        # Check primary key
        primary_key = contract.get('primary_key', [])
        if primary_key:
            if 'after' in event and event['after']:
                for pk_field in primary_key:
                    if pk_field not in event['after']:
                        violations.append(f"Missing primary key field in 'after': {pk_field}")
            elif 'before' in event and event['before']:
                for pk_field in primary_key:
                    if pk_field not in event['before']:
                        violations.append(f"Missing primary key field in 'before': {pk_field}")
        
        # Check schema fields
        schema = contract.get('schema', {})
        fields = schema.get('fields', {})
        
        if 'after' in event and event['after']:
            for field_name, field_def in fields.items():
                if field_name in event['after']:
                    # Check nullable
                    if not field_def.get('nullable', True) and event['after'][field_name] is None:
                        violations.append(f"Field {field_name} is nullable=false but value is null")
                    
                    # Check allowed values
                    allowed_values = field_def.get('allowed_values')
                    if allowed_values and event['after'][field_name] not in allowed_values:
                        violations.append(
                            f"Field {field_name} value '{event['after'][field_name]}' "
                            f"not in allowed values: {allowed_values}"
                        )
        
        return violations
    
    def validate_schema_evolution(self, old_contract: Dict[str, Any], 
                                   new_contract: Dict[str, Any]) -> List[str]:
        """
        Validate schema evolution follows policy
        
        Returns list of violation messages
        """
        violations = []
        evolution_policy = old_contract.get('schema_evolution_policy', {})
        
        old_schema = old_contract.get('schema', {}).get('fields', {})
        new_schema = new_contract.get('schema', {}).get('fields', {})
        
        # Check for dropped columns
        dropped_fields = set(old_schema.keys()) - set(new_schema.keys())
        if dropped_fields:
            drop_policy = evolution_policy.get('drop_column', {})
            if not drop_policy.get('allowed', False):
                violations.append(
                    f"Dropped fields without deprecation: {dropped_fields}. "
                    f"Policy: {drop_policy.get('rule', '')}"
                )
        
        # Check for type changes
        for field_name in old_schema.keys() & new_schema.keys():
            old_type = old_schema[field_name].get('type')
            new_type = new_schema[field_name].get('type')
            if old_type != new_type:
                change_policy = evolution_policy.get('change_type', {})
                if not change_policy.get('allowed', False):
                    violations.append(
                        f"Type change for {field_name}: {old_type} -> {new_type}. "
                        f"Policy: {change_policy.get('rule', '')}"
                    )
        
        # Check new fields are nullable or have defaults
        new_fields = set(new_schema.keys()) - set(old_schema.keys())
        if new_fields:
            add_policy = evolution_policy.get('add_column', {})
            for field_name in new_fields:
                field_def = new_schema[field_name]
                if not field_def.get('nullable', True) and 'default' not in field_def:
                    violations.append(
                        f"New field {field_name} must be nullable or have default. "
                        f"Policy: {add_policy.get('rule', '')}"
                    )
        
        return violations
    
    def validate_contract_file(self, contract_path: Path) -> Dict[str, Any]:
        """Validate contract file structure"""
        try:
            contract = self.load_contract(contract_path)
            
            # Basic structure checks
            required_sections = ['primary_key', 'schema']
            missing_sections = [s for s in required_sections if s not in contract]
            
            result = {
                'contract_path': str(contract_path),
                'valid': len(missing_sections) == 0,
                'violations': missing_sections,
                'contract': contract
            }
            
            return result
        except Exception as e:
            return {
                'contract_path': str(contract_path),
                'valid': False,
                'violations': [f"Error loading contract: {str(e)}"],
                'contract': None
            }
    
    def validate_all_contracts(self) -> Dict[str, Any]:
        """Validate all contracts in contracts directory"""
        results = {
            'timestamp': datetime.utcnow().isoformat(),
            'contracts': [],
            'total': 0,
            'valid': 0,
            'invalid': 0
        }
        
        # Validate CDC contracts
        cdc_dir = self.contracts_dir / 'cdc'
        if cdc_dir.exists():
            for contract_file in cdc_dir.glob('*.yaml'):
                result = self.validate_contract_file(contract_file)
                results['contracts'].append(result)
                results['total'] += 1
                if result['valid']:
                    results['valid'] += 1
                else:
                    results['invalid'] += 1
        
        # Validate Metrics contracts
        metrics_dir = self.contracts_dir / 'metrics'
        if metrics_dir.exists():
            for contract_file in metrics_dir.glob('*.yaml'):
                result = self.validate_contract_file(contract_file)
                results['contracts'].append(result)
                results['total'] += 1
                if result['valid']:
                    results['valid'] += 1
                else:
                    results['invalid'] += 1
        
        return results


def main():
    """CLI entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Validate data contracts')
    parser.add_argument('--contracts-dir', default='contracts',
                       help='Directory containing contract YAML files')
    parser.add_argument('--output', help='Output JSON file for results')
    parser.add_argument('--event', help='Validate single CDC event (JSON file)')
    parser.add_argument('--contract', help='Contract file to use for event validation')
    
    args = parser.parse_args()
    
    validator = ContractValidator(args.contracts_dir)
    
    if args.event and args.contract:
        # Validate single event
        contract = validator.load_contract(Path(args.contract))
        with open(args.event, 'r') as f:
            event = json.load(f)
        
        violations = validator.validate_cdc_event(contract, event)
        if violations:
            print("❌ Contract violations found:")
            for v in violations:
                print(f"  - {v}")
            exit(1)
        else:
            print("✅ Event is valid")
    else:
        # Validate all contracts
        results = validator.validate_all_contracts()
        
        if args.output:
            with open(args.output, 'w') as f:
                json.dump(results, f, indent=2)
            print(f"Results written to {args.output}")
        
        # Print summary
        print(f"\nContract Validation Summary:")
        print(f"  Total: {results['total']}")
        print(f"  Valid: {results['valid']}")
        print(f"  Invalid: {results['invalid']}")
        
        if results['invalid'] > 0:
            print("\n❌ Invalid contracts:")
            for contract_result in results['contracts']:
                if not contract_result['valid']:
                    print(f"  - {contract_result['contract_path']}")
                    for v in contract_result['violations']:
                        print(f"    - {v}")
            exit(1)
        else:
            print("\n✅ All contracts are valid")


if __name__ == '__main__':
    main()
