package net.kdt.pojavlaunch.value;
import net.kdt.pojavlaunch.*;
import java.io.*;
import com.google.gson.*;

public class MinecraftAccount
{
    public String accessToken = "0"; // access token
    public String clientToken = "0"; // clientID: refresh and invalidate
    public String profileId = "00000000-0000-0000-0000-000000000000"; // authenticate UUID
    public String username = "Steve";
    public String xuid;
    // Unique account ID: xuid for Microsoft accounts, profileId for third-party accounts, UUID for local accounts.
    // Matches native BaseAuthenticator.authData[@"accountId"] and is used as the account filename.
    public String accountId = "";

    public String save(String outPath) throws IOException {
        Tools.write(outPath, Tools.GLOBAL_GSON.toJson(this));
        return outPath;
    }

    public String save() throws IOException {
        // Use accountId (the unique identifier) as the filename to avoid collisions between accounts with the same name.
        String id = (accountId != null && !accountId.isEmpty()) ? accountId : username;
        return save(Tools.DIR_ACCOUNT_NEW + "/" + id + ".json");
    }

    public static MinecraftAccount parse(String content) throws JsonSyntaxException {
        MinecraftAccount account = Tools.GLOBAL_GSON.fromJson(content, MinecraftAccount.class);
        // Read access token from keychain
        if (account.xuid != null) {
            account.accessToken = getAccessTokenFromKeychain(account.xuid);
        }
        return account;
    }

    public static MinecraftAccount load(String name) throws IOException, JsonSyntaxException {
        // name is accountId (passed as args[0] to native launchJVM) and is used as the account filename.
        MinecraftAccount acc = parse(Tools.read(Tools.DIR_ACCOUNT_NEW + "/" + name + ".json"));
        if (acc.accessToken == null) {
            acc.accessToken = "0";
        } if (acc.clientToken == null) {
            acc.clientToken = "0";
        } if (acc.profileId == null) {
            acc.profileId = "0";
        } if (acc.username == null) {
            acc.username = "0";
        } if (acc.xuid == null) {
            acc.xuid = "0";
        }
        // Fallback accountId: prefer the name argument (native accountId), then xuid, and finally profileId.
        if (acc.accountId == null || acc.accountId.isEmpty()) {
            acc.accountId = name;
        }
        return acc;
    }

    static {
        System.loadLibrary("AmethystAccountJNI");
    }
    public static native String getAccessTokenFromKeychain(String xuid);
}
