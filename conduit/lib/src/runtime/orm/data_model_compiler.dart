import 'package:conduit/src/db/managed/managed.dart';
import 'package:conduit/src/runtime/orm/entity_builder.dart';
import 'package:conduit_runtime/runtime.dart';
import 'package:reflectable/reflectable.dart';

class DataModelCompiler extends Compiler {
  @override
  Map<Type, dynamic> compile(MirrorContext context) {
    final m = <Type, dynamic>{};

    final instanceTypes = context.types
        .where(_isTypeManagedObjectSubclass)
        .map((c) => c.reflectedType);

    _builders = instanceTypes.map((t) => EntityBuilder(t)).toList();
    _builders!.forEach((b) {
      b.compile(_builders);
    });
    _validate();

    _builders!.forEach((b) {
      b.link(_builders!.map((eb) => eb.entity).toList());
      m[b.entity.instanceType] = b.runtime;
    });

    return m;
  }

  List<EntityBuilder>? _builders;

  void _validate() {
    // Check for dupe tables
    _builders!.forEach((builder) {
      final withSameName = _builders!
          .where((eb) => eb.name == builder.name)
          .map((eb) => eb.instanceTypeName)
          .toList();
      if (withSameName.length > 1) {
        throw ManagedDataModelErrorImpl.duplicateTables(
            builder.name, withSameName);
      }
    });

    _builders!.forEach((b) => b.validate(_builders));
  }

  static bool _isTypeManagedObjectSubclass(ClassMirror mirror) {
    final managedObjectMirror = runtimeReflector.reflectType(ManagedObject);

    if (!mirror.isSubclassOf(managedObjectMirror as ClassMirror)) {
      return false;
    }

    if (!mirror.hasReflectedType) {
      return false;
    }

    if (mirror == managedObjectMirror) {
      return false;
    }

    // mirror.mixin: If this class is the result of a mixin application of the form S with M, returns a class mirror on M.
    // Otherwise returns a class mirror on the reflectee.
    if (mirror.mixin != mirror) {
      return false;
    }

    return true;
  }
}

class ManagedDataModelErrorImpl extends ManagedDataModelError {
  ManagedDataModelErrorImpl(String message) : super(message);

  factory ManagedDataModelErrorImpl.noPrimaryKey(ManagedEntity entity) {
    return ManagedDataModelErrorImpl(
        "Class '${_getPersistentClassName(entity)}'"
        " doesn't declare a primary key property or declares more than one primary key. All 'ManagedObject' subclasses "
        "must have a primary key. Usually, this means you want to add '@primaryKey int id;' "
        "to ${_getPersistentClassName(entity)}, but if you want more control over "
        "the type of primary key, declare the property as one of "
        "${ManagedType.supportedDartTypes.join(", ")} and "
        "add '@Column(primaryKey: true)' above it.");
  }

  factory ManagedDataModelErrorImpl.invalidType(
      String tableSymbol, String propertySymbol) {
    return ManagedDataModelErrorImpl("Property '${propertySymbol}' on "
        "'${tableSymbol}'"
        " has an unsupported type. This can occur when the type cannot be stored in a database, or when"
        " a relationship does not have a valid inverse. If this property is supposed to be a relationship, "
        " ensure the inverse property annotation is 'Relate(#${propertySymbol}, ...)'."
        " If this is not supposed to be a relationship property, its type must be one of: ${ManagedType.supportedDartTypes.join(", ")}.");
  }

  factory ManagedDataModelErrorImpl.invalidMetadata(
      String tableName, String property) {
    return ManagedDataModelErrorImpl("Relationship '${property}' on "
        "'$tableName' "
        "cannot both have 'Column' and 'Relate' metadata. "
        "To add flags for indexing or nullability to a relationship, see the constructor "
        "for 'Relate'.");
  }

  factory ManagedDataModelErrorImpl.missingInverse(
      String tableName,
      String instanceName,
      String property,
      String destinationTableName,
      String? expectedProperty) {
    var expectedString = "Some property";
    if (expectedProperty != null) {
      expectedString = "'${expectedProperty}'";
    }
    return ManagedDataModelErrorImpl("Relationship '${property}' on "
        "'${tableName}' has "
        "no inverse property. Every relationship must have an inverse. "
        "$expectedString on "
        "'${destinationTableName}'"
        "is supposed to exist, and it should be either a "
        "'${instanceName}' or"
        "'ManagedSet<${instanceName}>'.");
  }

  factory ManagedDataModelErrorImpl.incompatibleDeleteRule(
      String tableName, String property) {
    return ManagedDataModelErrorImpl("Relationship '${property}' on "
        "'$tableName' "
        "has both 'RelationshipDeleteRule.nullify' and 'isRequired' equal to true, which "
        "couldn't possibly be true at the same. 'isRequired' means the column "
        "can't be null and 'nullify' means the column has to be null.");
  }

  factory ManagedDataModelErrorImpl.dualMetadata(String tableName,
      String property, String destinationTableName, String? inverseProperty) {
    return ManagedDataModelErrorImpl("Relationship '${property}' "
        "on '${tableName}' "
        "and '${inverseProperty}' "
        "on '${destinationTableName}' "
        "both have 'Relate' metadata, but only one can. "
        "The property with 'Relate' metadata is a foreign key column "
        "in the database.");
  }

  factory ManagedDataModelErrorImpl.duplicateInverse(
      String tableName, String? inverseName, List<String?> conflictingNames) {
    return ManagedDataModelErrorImpl(
        "Entity '${tableName}' has multiple relationship "
        "properties that claim to be the inverse of '$inverseName'. A property may "
        "only have one inverse. The claiming properties are: ${conflictingNames.join(", ")}.");
  }

  factory ManagedDataModelErrorImpl.noDestinationEntity(
      String tableName, String property, String expectedType) {
    return ManagedDataModelErrorImpl("Relationship '${property}' on "
        "'${tableName}' expects that there is a subclass "
        "of 'ManagedObject' named '${expectedType}', "
        "but there isn't one. If you have declared one - and you really checked "
        "hard for typos - make sure the file it is declared in is imported appropriately.");
  }

  factory ManagedDataModelErrorImpl.multipleDestinationEntities(
      String tableName,
      String property,
      List<String> possibleEntities,
      String expected) {
    return ManagedDataModelErrorImpl("Relationship '${property}' on "
        "'${tableName}' expects that just one "
        "'ManagedObject' subclass uses a table definition that extends "
        "'${expected}. But the following implementations were found: "
        "${possibleEntities.join(",")}. That's just "
        "how it is for now.");
  }

  factory ManagedDataModelErrorImpl.invalidTransient(
      ManagedEntity entity, Symbol property) {
    return ManagedDataModelErrorImpl("Transient property '${property}' on "
        "'${_getInstanceClassName(entity)}' declares that"
        "it is transient, but it it has a mismatch. A transient "
        "getter method must have 'isAvailableAsOutput' and a transient "
        "setter method must have 'isAvailableAsInput'.");
  }

  factory ManagedDataModelErrorImpl.noConstructor(ClassMirror cm) {
    final name = cm.simpleName;
    return ManagedDataModelErrorImpl("Invalid 'ManagedObject' subclass "
        "'$name' does not implement default, unnamed constructor. "
        "Add '$name();' to the class declaration.");
  }

  factory ManagedDataModelErrorImpl.duplicateTables(
      String? tableName, List<String> instanceTypes) {
    return ManagedDataModelErrorImpl(
        "Entities ${instanceTypes.map((i) => "'$i'").join(",")} "
        "have the same table name: '$tableName'. Rename these "
        "the table definitions, or add a '@Table(name: ...)' annotation to the table definition.");
  }

  factory ManagedDataModelErrorImpl.conflictingTypes(
      ManagedEntity entity, String propertyName) {
    return ManagedDataModelErrorImpl(
        "The entity '${_getInstanceClassName(entity)}' declares two accessors named "
        "'$propertyName', but they have conflicting types.");
  }

  factory ManagedDataModelErrorImpl.invalidValidator(
      ManagedEntity entity, String property, String reason) {
    return ManagedDataModelErrorImpl(
        "Type '${_getPersistentClassName(entity)}' "
        "has invalid validator for property '$property'. Reason: $reason");
  }

  factory ManagedDataModelErrorImpl.emptyEntityUniqueProperties(
      String tableName) {
    return ManagedDataModelErrorImpl("Type '$tableName' "
        "has empty set for unique 'Table'. Must contain two or "
        "more attributes (or belongs-to relationship properties).");
  }

  factory ManagedDataModelErrorImpl.singleEntityUniqueProperty(
      String tableName, String property) {
    return ManagedDataModelErrorImpl("Type '$tableName' "
        "has only one attribute for unique 'Table'. Must contain two or "
        "more attributes (or belongs-to relationship properties). To make this property unique, "
        "add 'Column(unique: true)' to declaration of '${property}'.");
  }

  factory ManagedDataModelErrorImpl.invalidEntityUniqueProperty(
      String tableName, Symbol property) {
    return ManagedDataModelErrorImpl("Type '${tableName}' "
        "declares '${property}' as unique in 'Table', "
        "but '${property}' is not a property of this type.");
  }

  factory ManagedDataModelErrorImpl.relationshipEntityUniqueProperty(
      String tableName, Symbol property) {
    return ManagedDataModelErrorImpl("Type '${tableName}' "
        "declares '${property}' as unique in 'Table'. This property cannot "
        "be used to make an instance unique; only attributes or belongs-to relationships may used "
        "in this way.");
  }

  static String? _getPersistentClassName(ManagedEntity entity) {
    // if (entity == null) {
    //   return null;
    // }

    // if (entity.tableDefinition == null) {
    //   return null;
    // }

    return entity.tableDefinition;
  }

  static String _getInstanceClassName(ManagedEntity entity) {
    // if (entity.instanceType == null) {
    //   return null;
    // }

    return runtimeReflector.reflectType(entity.instanceType).simpleName;
  }
}
