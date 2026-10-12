/*
 * Decompiled with CFR 0.152.
 */
package com.metallum.asm.commons;

import com.metallum.asm.ConstantDynamic;
import com.metallum.asm.Handle;
import com.metallum.asm.Type;
import com.metallum.asm.commons.SignatureRemapper;
import com.metallum.asm.signature.SignatureReader;
import com.metallum.asm.signature.SignatureVisitor;
import com.metallum.asm.signature.SignatureWriter;

public abstract class Remapper {
    private static final String LAMBDA_FACTORY_CLASSNAME = "java/lang/invoke/LambdaMetafactory";
    private static final String LAMBDA_FACTORY_METAFACTORY = "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;";
    private static final String LAMBDA_FACTORY_ALTMETAFACTORY = "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;[Ljava/lang/Object;)Ljava/lang/invoke/CallSite;";
    final int api;

    @Deprecated
    protected Remapper() {
        this.api = 0;
    }

    protected Remapper(int api) {
        if (api != 589824 && api != 524288 && api != 458752 && api != 393216 && api != 327680 && api != 262144 && api != 0x10A0000) {
            throw new IllegalArgumentException(Remapper.stringConcat$0(api));
        }
        this.api = api;
    }

    private static /* synthetic */ String stringConcat$0(int n) {
        return "Unsupported api " + n;
    }

    public String mapDesc(String descriptor) {
        return this.mapType(Type.getType(descriptor)).getDescriptor();
    }

    private Type mapType(Type type) {
        switch (type.getSort()) {
            case 9: {
                StringBuilder remappedDescriptor = new StringBuilder();
                for (int i = 0; i < type.getDimensions(); ++i) {
                    remappedDescriptor.append('[');
                }
                remappedDescriptor.append(this.mapType(type.getElementType()).getDescriptor());
                return Type.getType(remappedDescriptor.toString());
            }
            case 10: {
                String remappedInternalName = this.map(type.getInternalName());
                return remappedInternalName != null ? Type.getObjectType(remappedInternalName) : type;
            }
            case 11: {
                return Type.getMethodType(this.mapMethodDesc(type.getDescriptor()));
            }
        }
        return type;
    }

    public String mapType(String internalName) {
        if (internalName == null) {
            return null;
        }
        return this.mapType(Type.getObjectType(internalName)).getInternalName();
    }

    public String[] mapTypes(String[] internalNames) {
        String[] remappedInternalNames = null;
        for (int i = 0; i < internalNames.length; ++i) {
            String internalName = internalNames[i];
            String remappedInternalName = this.mapType(internalName);
            if (remappedInternalName == null) continue;
            if (remappedInternalNames == null) {
                remappedInternalNames = (String[])internalNames.clone();
            }
            remappedInternalNames[i] = remappedInternalName;
        }
        return remappedInternalNames != null ? remappedInternalNames : internalNames;
    }

    public String mapMethodDesc(String methodDescriptor) {
        if ("()V".equals(methodDescriptor)) {
            return methodDescriptor;
        }
        StringBuilder stringBuilder = new StringBuilder("(");
        for (Type argumentType : Type.getArgumentTypes(methodDescriptor)) {
            stringBuilder.append(this.mapType(argumentType).getDescriptor());
        }
        Type returnType = Type.getReturnType(methodDescriptor);
        if (returnType == Type.VOID_TYPE) {
            stringBuilder.append(")V");
        } else {
            stringBuilder.append(')').append(this.mapType(returnType).getDescriptor());
        }
        return stringBuilder.toString();
    }

    public Object mapValue(Object value) {
        if (value instanceof Type) {
            return this.mapType((Type)value);
        }
        if (value instanceof Handle) {
            Handle handle = (Handle)value;
            boolean isFieldHandle = handle.getTag() <= 4;
            return new Handle(handle.getTag(), this.mapType(handle.getOwner()), isFieldHandle ? this.mapFieldName(handle.getOwner(), handle.getName(), handle.getDesc()) : this.mapMethodName(handle.getOwner(), handle.getName(), handle.getDesc()), isFieldHandle ? this.mapDesc(handle.getDesc()) : this.mapMethodDesc(handle.getDesc()), handle.isInterface());
        }
        if (value instanceof ConstantDynamic) {
            ConstantDynamic constantDynamic = (ConstantDynamic)value;
            String name = constantDynamic.getName();
            String descriptor = constantDynamic.getDescriptor();
            Handle bootstrapMethod = constantDynamic.getBootstrapMethod();
            int bootstrapMethodArgumentCount = constantDynamic.getBootstrapMethodArgumentCount();
            Object[] bootstrapMethodArguments = new Object[bootstrapMethodArgumentCount];
            Object[] remappedBootstrapMethodArguments = new Object[bootstrapMethodArgumentCount];
            for (int i = 0; i < bootstrapMethodArgumentCount; ++i) {
                bootstrapMethodArguments[i] = constantDynamic.getBootstrapMethodArgument(i);
                remappedBootstrapMethodArguments[i] = this.mapValue(bootstrapMethodArguments[i]);
            }
            name = this.api == 0 ? this.mapInvokeDynamicMethodName(name, descriptor) : this.mapInvokeDynamicMethodName(name, descriptor, bootstrapMethod, bootstrapMethodArguments);
            return new ConstantDynamic(name, this.mapDesc(descriptor), (Handle)this.mapValue(bootstrapMethod), remappedBootstrapMethodArguments);
        }
        return value;
    }

    public String mapSignature(String signature, boolean typeSignature) {
        if (signature == null) {
            return null;
        }
        SignatureReader signatureReader = new SignatureReader(signature);
        SignatureWriter signatureWriter = new SignatureWriter();
        SignatureVisitor signatureRemapper = this.createSignatureRemapper(signatureWriter);
        if (typeSignature) {
            signatureReader.acceptType(signatureRemapper);
        } else {
            signatureReader.accept(signatureRemapper);
        }
        return signatureWriter.toString();
    }

    @Deprecated
    protected SignatureVisitor createRemappingSignatureAdapter(SignatureVisitor signatureVisitor) {
        return this.createSignatureRemapper(signatureVisitor);
    }

    protected SignatureVisitor createSignatureRemapper(SignatureVisitor signatureVisitor) {
        return new SignatureRemapper(signatureVisitor, this);
    }

    public String mapAnnotationAttributeName(String descriptor, String name) {
        return name;
    }

    public String mapInnerClassName(String name, String ownerName, String innerName) {
        String remappedInnerName = this.mapType(name);
        if (remappedInnerName.equals(name)) {
            return innerName;
        }
        int originSplit = name.lastIndexOf(47);
        int remappedSplit = remappedInnerName.lastIndexOf(47);
        if (originSplit != -1 && remappedSplit != -1 && name.substring(originSplit).equals(remappedInnerName.substring(remappedSplit))) {
            return innerName;
        }
        if (remappedInnerName.contains("$")) {
            int index;
            for (index = remappedInnerName.lastIndexOf(36) + 1; index < remappedInnerName.length() && Character.isDigit(remappedInnerName.charAt(index)); ++index) {
            }
            return remappedInnerName.substring(index);
        }
        return innerName;
    }

    public String mapMethodName(String owner, String name, String descriptor) {
        return name;
    }

    @Deprecated
    public String mapInvokeDynamicMethodName(String name, String descriptor) {
        return name;
    }

    public String mapInvokeDynamicMethodName(String name, String descriptor, Handle bootstrapMethodHandle, Object ... bootstrapMethodArguments) {
        String mappedWellKnownName = this.mapWellKnownInvokeDynamicMethodName(name, descriptor, bootstrapMethodHandle, bootstrapMethodArguments);
        if (mappedWellKnownName != null) {
            return mappedWellKnownName;
        }
        return this.mapBasicInvokeDynamicMethodName(name, descriptor, bootstrapMethodHandle, bootstrapMethodArguments);
    }

    public String mapWellKnownInvokeDynamicMethodName(String name, String descriptor, Handle bootstrapMethodHandle, Object ... bootstrapMethodArguments) {
        if (LAMBDA_FACTORY_CLASSNAME.equals(bootstrapMethodHandle.getOwner()) && bootstrapMethodHandle.getTag() == 6) {
            boolean isMetafactory = false;
            isMetafactory |= "metafactory".equals(bootstrapMethodHandle.getName()) && LAMBDA_FACTORY_METAFACTORY.equals(bootstrapMethodHandle.getDesc());
            if (isMetafactory |= "altMetafactory".equals(bootstrapMethodHandle.getName()) && LAMBDA_FACTORY_ALTMETAFACTORY.equals(bootstrapMethodHandle.getDesc())) {
                return this.mapMethodName(Type.getReturnType(descriptor).getInternalName(), name, bootstrapMethodArguments[0].toString());
            }
        }
        return null;
    }

    public String mapBasicInvokeDynamicMethodName(String name, String descriptor, Handle bootstrapMethodHandle, Object ... bootstrapMethodArguments) {
        return name;
    }

    public String mapRecordComponentName(String owner, String name, String descriptor) {
        return name;
    }

    public String mapFieldName(String owner, String name, String descriptor) {
        return name;
    }

    public String mapPackageName(String name) {
        return name;
    }

    public String mapModuleName(String name) {
        return name;
    }

    public String map(String internalName) {
        return internalName;
    }
}

