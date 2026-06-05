---
name: build-tooling
description: |
  Maven and Gradle build tool conventions for Java projects: build tool detection, wrapper usage, dependency management, BOMs, plugin configuration, semver, and multi-module layouts. Stack-agnostic — referenced by every Java plugin in the marketplace.

  Use this skill to:
  - Detect which build tool is in use and invoke it correctly.
  - Manage dependencies safely (BOMs, version properties, no wildcard versions).
  - Configure compiler, test, and code-quality plugins.
  - Handle multi-module projects.

  Do NOT use this skill for:
  - Framework-specific build plugins (Spring Boot Gradle plugin — in spring-boot-plugin:spring-conventions).
  - CI/CD pipeline config.
---

# Build Tooling (Maven & Gradle, stack-agnostic)

## Build tool detection

Determine the build tool at the start of every task:

| Signal | Tool |
|---|---|
| `pom.xml` exists | Maven |
| `build.gradle` exists | Gradle (Groovy DSL) |
| `build.gradle.kts` exists | Gradle (Kotlin DSL) |
| Both `pom.xml` and `build.gradle*` | Unusual — flag and ask; never assume |

## Always use the wrapper

Never invoke `mvn` or `gradle` directly — use the wrapper so the team's pinned version runs.

```bash
# Maven
./mvnw <goal>            # Unix
mvnw.cmd <goal>          # Windows (if needed)

# Gradle
./gradlew <task>
```

If the wrapper is absent, flag it in DECISIONS and fall back to the system binary, but note that pinning is missing.

## Maven — key conventions

### Dependency management

```xml
<!-- Declare versions in <properties> — never inline literals -->
<properties>
    <java.version>21</java.version>
    <mapstruct.version>1.6.3</mapstruct.version>
</properties>

<!-- Import a BOM in dependencyManagement to align a family of deps -->
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>${spring-boot.version}</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<!-- Declare individual deps without <version> when BOM covers them -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>
```

**Never** use `LATEST` or `RELEASE` as versions — they are non-reproducible. Pin explicitly or let a BOM manage.

### Useful goals

```bash
./mvnw compile                          # compile only
./mvnw test                             # compile + test
./mvnw package -DskipTests              # build JAR/WAR, skip tests
./mvnw verify                           # full build incl. integration tests
./mvnw dependency:tree                  # show resolved dependency tree
./mvnw versions:display-dependency-updates   # check for outdated deps
```

### Multi-module Maven

Root `pom.xml` declares `<packaging>pom</packaging>` and `<modules>` list. Child modules inherit `groupId` and `version` from parent. Use `<dependencyManagement>` in root to align versions across modules — child modules do not repeat versions.

## Gradle — key conventions

### Kotlin DSL (build.gradle.kts) — preferred in new projects

```kotlin
plugins {
    java
    application
}

group = "com.example"
version = "1.0.0"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    // Import a BOM (platform)
    implementation(platform("io.quarkus:quarkus-bom:3.18.0"))
    implementation("io.quarkus:quarkus-resteasy-reactive")

    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
}
```

### Groovy DSL (build.gradle) — legacy projects

```groovy
plugins {
    id 'java'
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

dependencies {
    implementation platform('io.quarkus:quarkus-bom:3.18.0')
    implementation 'io.quarkus:quarkus-resteasy-reactive'

    testImplementation 'org.junit.jupiter:junit-jupiter'
}

test {
    useJUnitPlatform()
}
```

### Useful tasks

```bash
./gradlew build            # compile + test + assemble
./gradlew test             # test only
./gradlew assemble         # build without tests
./gradlew dependencies     # dependency tree
./gradlew dependencyUpdates  # with ben-manes/versions plugin
```

### Java toolchain (Gradle 7.6+)

Prefer `java { toolchain { ... } }` over `sourceCompatibility` / `targetCompatibility`. The toolchain block pins the JDK version independently of the JDK running Gradle itself, ensuring reproducibility across machines.

## Dependency version discipline

- **Use a BOM** for any framework with a family of aligned artifacts (Spring Boot, Quarkus, Micronaut).
- **Declare versions in one place** — Maven `<properties>`, Gradle `libs.versions.toml` (version catalog), or the BOM.
- **No wildcard or range versions** (`[1.0,)`, `LATEST`, `RELEASE`, `+`).
- **Test-scope only** for test frameworks (JUnit, Mockito, AssertJ, Testcontainers).
- **Provided/compileOnly** for things the container supplies at runtime (Jakarta EE APIs, `lombok` annotations if used).

## Adding a new dependency — checklist

1. Check if the BOM already manages the version — if so, omit the version.
2. Add to the correct scope (`implementation` / `testImplementation` / `compileOnly`).
3. Verify no transitive conflict: run `./mvnw dependency:tree` or `./gradlew dependencies`.
4. Record in DECISIONS if adding a new non-trivial dependency.

## Common Maven plugins (when not already configured)

```xml
<!-- Enforce minimum Maven version and dependency convergence -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-enforcer-plugin</artifactId>
    <executions>
        <execution>
            <id>enforce</id>
            <goals><goal>enforce</goal></goals>
            <configuration>
                <rules>
                    <requireMavenVersion><version>3.8</version></requireMavenVersion>
                    <dependencyConvergence/>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

Do not add plugins that aren't already present unless the BA spec calls for it — document in DECISIONS.
